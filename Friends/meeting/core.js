// The meeting point: introduces Macs whose players have BOTH added each other, and passes their sealed notes. Nothing else.
// It keeps no friend lists and no addresses. The only thing stored is an unanswered friend request, for 7 days.
// Runs the same inside a Cloudflare Durable Object (worker.js) and in the local test server (test/server.mjs).
export const LIMITS = {
  message: 6144, body: 4096, friends: 32, name: 24, authMs: 10000,
  perMinute: 240, requestsPerHour: 10, pending: 20, requestDays: 7, sockets: 200, unproven: 50, perPlace: 20, requestsPerPlace: 30, held: 1000,
  turnPerHour: 6, turnPerPlace: 12, turnPerDay: 60, turnSeconds: 3 * 3600,
};
const ID = /^[0-9A-HJKMNP-TV-Z]{16}$/, B64 = /^[A-Za-z0-9+/]+={0,2}$/;
const te = new TextEncoder();
const bytes = (s, n) => { if (typeof s !== 'string' || !B64.test(s)) return null; let b; try { b = Uint8Array.from(atob(s), c => c.charCodeAt(0)); } catch { return null; } return n === undefined || b.length === n ? b : null; };
const b64 = u => btoa(String.fromCharCode(...u));
const join = (...p) => { const o = new Uint8Array(p.reduce((n, x) => n + x.length, 0)); let i = 0; for (const x of p) { o.set(x, i); i += x.length; } return o; };
const same = (a, b) => { if (a.length !== b.length) return false; let x = 0; for (let i = 0; i < a.length; i++) x |= a[i] ^ b[i]; return x === 0; };
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

// A friend code is the first 80 bits of a hash of the player's public key
export async function codeOf(key) {
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', join(te.encode('docked-friend-code-v1'), key)));
  let s = '', acc = 0, n = 0;
  for (let i = 0; i < 10; i++) { acc = acc << 8 | h[i]; n += 8; while (n >= 5) { n -= 5; s += ALPHABET[acc >> n & 31]; } acc &= (1 << n) - 1; }
  return s;
}

// Printable, short, one line, nothing that rearranges text on screen
export function cleanName(s) {
  if (typeof s !== 'string') return '';
  const t = s.normalize('NFC').replace(/[\p{C}\p{Zl}\p{Zp}]/gu, '').trim();
  return [...t].slice(0, LIMITS.name).join('');
}

// A socket here has: att (a small saved object), send(text), close(code)
// store: get(k), put(k, v), delete(k), list(prefix) -> Map   turn: async (seconds) -> iceServers or null
export class Meeting {
  constructor({ store, sockets, circleKey, host, turn, now = () => Date.now() }) {
    if (!(circleKey instanceof Uint8Array) || circleKey.length !== 32) throw new Error('the circle key must be 32 bytes');
    Object.assign(this, { store, sockets, circleKey, host, turn, now });
    this.rates = new Map();
  }

  // place: the internet address the connection came from, used only to limit abuse, never stored or shown
  open(ws, place = '') {
    const all = [...this.sockets()].filter(o => o !== ws), waiting = all.filter(o => o.att?.nonce);
    if (place && all.filter(o => o.att?.place === place).length >= LIMITS.perPlace) { ws.close(1013); return; }
    if (all.length - waiting.length >= LIMITS.sockets) { ws.close(1013); return; }
    if (waiting.length >= LIMITS.unproven) waiting.sort((a, b) => a.att.at - b.att.at)[0].close(1013);   // the one that has waited longest makes room, so silent connections cannot lock players out
    const nonce = b64(crypto.getRandomValues(new Uint8Array(32)));
    ws.att = { nonce, at: this.now(), place };
    ws.send(JSON.stringify({ t: 'hello', v: 1, nonce }));
  }

  rate(key, max, ms) {
    const t = this.now(), r = this.rates.get(key);
    if (this.rates.size > 5000) for (const [k, v] of this.rates) if (v.until <= t) this.rates.delete(k);
    if (!r || r.until <= t) { this.rates.set(key, { n: 1, until: t + ms }); return true; }
    return ++r.n <= max;
  }

  async message(ws, text) {
    const bad = () => ws.close(1008);
    if (typeof text !== 'string' || text.length > LIMITS.message) return bad();
    let m; try { m = JSON.parse(text); } catch { return bad(); }
    if (!m || typeof m !== 'object' || Array.isArray(m)) return bad();
    const a = ws.att;
    if (!a) return bad();
    if (!a.id) return m.t === 'auth' ? this.auth(ws, m) : bad();
    if (!this.rate('m' + a.id, LIMITS.perMinute, 60000)) { if (this.rates.get('m' + a.id).n > LIMITS.perMinute * 4) bad(); return; }
    switch (m.t) {
      case 'watch': return this.watch(ws, m);
      case 'state': return this.state(ws, m);
      case 'send': return this.pass(ws, m);
      case 'request': return this.request(ws, m);
      case 'answered': return this.answered(ws, m);
      case 'turn': return this.relay(ws);
      case 'ping': return ws.send('{"t":"pong"}');
      default: return bad();
    }
  }

  // Proves two things: this copy was patched for this circle, and the player holds the private key behind the code
  async auth(ws, m) {
    const a = ws.att, key = bytes(m.key, 65), sig = bytes(m.sig, 64), mac = bytes(m.mac, 32);
    const fail = () => { ws.att = null; ws.close(1008); };
    if (!a.nonce || !key || !sig || !mac || this.now() - a.at > LIMITS.authMs) return fail();
    ws.att = { used: 1 };   // one try per connection, even while the checks below wait
    const said = join(te.encode('docked-meet-v1|' + this.host + '|'), bytes(a.nonce, 32), key);
    const hk = await crypto.subtle.importKey('raw', this.circleKey, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const want = new Uint8Array(await crypto.subtle.sign('HMAC', hk, said));
    if (!same(want, mac)) return fail();
    let ok = false;
    try { const pk = await crypto.subtle.importKey('raw', key, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
      ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, pk, sig, said); } catch { ok = false; }
    if (!ok) return fail();
    const id = await codeOf(key);
    for (const o of this.sockets()) if (o !== ws && o.att?.id === id) { const was = o.att; o.att = { gone: 1 }; this.tell(was, false); o.close(4001); }   // the newest copy of a player wins
    ws.att = { id, watch: [], ready: false, place: a.place };
    ws.send(JSON.stringify({ t: 'ready', id, relay: !!this.turn }));
    const t = this.now();
    for (const [k, r] of await this.store.list('r:' + id + ':')) {
      if (r.until <= t) await this.store.delete(k);
      else ws.send(JSON.stringify({ t: 'request', from: r.from, name: r.name }));
    }
  }

  live(id) { for (const o of this.sockets()) if (o.att?.id === id) return o; return null; }
  mutual(a, b) { return a !== b && a.watch.includes(b.id) && b.watch.includes(a.id); }
  tell(a, on) { for (const o of this.sockets()) if (o.att?.id && this.mutual(a, o.att)) o.send(JSON.stringify({ t: 'peer', id: a.id, on, ready: on && a.ready })); }

  watch(ws, m) {
    const ids = m.ids;
    if (!Array.isArray(ids) || ids.length > LIMITS.friends || ids.some(x => typeof x !== 'string' || !ID.test(x))) return ws.close(1008);
    const a = ws.att, before = a.watch, next = [...new Set(ids)].filter(x => x !== a.id);
    for (const id of before) if (!next.includes(id)) { const o = this.live(id); if (o && this.mutual(a, o.att)) { o.send(JSON.stringify({ t: 'peer', id: a.id, on: false, ready: false })); ws.send(JSON.stringify({ t: 'peer', id, on: false, ready: false })); } }
    const b = { ...a, watch: next }; ws.att = b;
    for (const id of next) if (!before.includes(id)) {
      const o = this.live(id); if (!o || !this.mutual(b, o.att)) continue;
      ws.send(JSON.stringify({ t: 'peer', id, on: true, ready: o.att.ready })); o.send(JSON.stringify({ t: 'peer', id: a.id, on: true, ready: b.ready }));
    }
  }

  state(ws, m) {
    if (typeof m.ready !== 'boolean') return ws.close(1008);
    ws.att = { ...ws.att, ready: m.ready }; this.tell(ws.att, true);
  }

  pass(ws, m) {
    if (typeof m.to !== 'string' || !ID.test(m.to) || typeof m.body !== 'string' || m.body.length > LIMITS.body) return ws.close(1008);
    const o = this.live(m.to); if (!o || !this.mutual(ws.att, o.att)) return;   // the same silence for a stranger, an offline friend and a code nobody has
    o.send(JSON.stringify({ t: 'from', id: ws.att.id, body: m.body }));
  }

  // "I would like to be your friend". Kept for a player who is away. Says nothing back about whether the code exists.
  async request(ws, m) {
    const a = ws.att;
    if (typeof m.to !== 'string' || !ID.test(m.to) || m.to === a.id) return ws.close(1008);
    if (!this.rate('r' + a.id, LIMITS.requestsPerHour, 3600000) || (a.place && !this.rate('R' + a.place, LIMITS.requestsPerPlace, 3600000))) { ws.send('{"t":"slow"}'); return; }
    const k = 'r:' + m.to + ':' + a.id, t = this.now(), r = { from: a.id, name: cleanName(m.name), until: t + LIMITS.requestDays * 86400000 };
    const mine = await this.store.list('r:' + m.to + ':'); let held = 0;
    for (const [x, v] of mine) { if (v.until <= t) await this.store.delete(x); else if (x !== k) held++; }
    if (held < LIMITS.pending && (mine.has(k) || (await this.store.list('r:')).size < LIMITS.held)) { await this.store.put(k, r); const o = this.live(m.to); if (o) o.send(JSON.stringify({ t: 'request', from: r.from, name: r.name })); }
    ws.send(JSON.stringify({ t: 'asked', to: m.to }));
  }

  // The player accepted or declined: forget the request either way. Accepting is adding the code to one's own watch list.
  async answered(ws, m) {
    if (typeof m.from !== 'string' || !ID.test(m.from)) return ws.close(1008);
    await this.store.delete('r:' + ws.att.id + ':' + m.from);
  }

  async relay(ws) {
    const a = ws.att, none = () => { if (ws.att?.id) ws.send('{"t":"turn","servers":null}'); };
    let friend = false; for (const o of this.sockets()) if (o.att?.id && o.att.ready && this.mutual(a, o.att)) friend = true;
    if (!this.turn || !a.ready || !friend || !this.rate('t' + a.id, LIMITS.turnPerHour, 3600000) || (a.place && !this.rate('T' + a.place, LIMITS.turnPerPlace, 86400000))) return none();
    const day = 'd:' + new Date(this.now()).toISOString().slice(0, 10), used = (await this.store.get(day)) || 0;
    if (used >= LIMITS.turnPerDay) return none();
    await this.store.put(day, used + 1);
    if (used === 0) for (const k of (await this.store.list('d:')).keys()) if (k !== day) await this.store.delete(k);
    let s = null; try { s = await this.turn(LIMITS.turnSeconds); } catch { s = null; }
    if (!s) return none();
    if (ws.att?.id) ws.send(JSON.stringify({ t: 'turn', servers: s }));
  }

  close(ws) { const a = ws.att; if (a?.id) { ws.att = { gone: 1 }; this.tell(a, false); } }

  // Connections that never proved themselves
  sweep() { const t = this.now(); for (const o of this.sockets()) if (o.att?.nonce && t - o.att.at > LIMITS.authMs) o.close(1008); }
}
