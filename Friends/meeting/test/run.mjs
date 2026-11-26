import { serve } from './server.mjs';
import { codeOf, cleanName, LIMITS } from '../core.js';
import { webcrypto as wc, randomBytes } from 'node:crypto';
let pass = 0, fail = 0; const ok = (c, m) => { if (c) pass++; else { fail++; console.log('FAIL', m); } };
const circle = new Uint8Array(randomBytes(32)); let clock = Date.now(), turns = 0;
const s = await serve(0, circle, { turn: async () => { turns++; return { username: 'u', credential: 'c' }; }, now: () => clock });
const b64 = u => Buffer.from(u).toString('base64'), sleep = ms => new Promise(r => setTimeout(r, ms));
async function person() { const k = await wc.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']); const key = new Uint8Array(await wc.subtle.exportKey('raw', k.publicKey)); return { k, key, id: await codeOf(key) }; }
async function connect(p, o = {}) {
  const ws = new WebSocket(`ws://127.0.0.1:${s.port}/meet`), got = []; let closed = 0;
  const c = { got, p, send: m => ws.send(typeof m === 'string' ? m : JSON.stringify(m)), raw: ws, get closed() { return closed; }, close: () => ws.close(),
    of: t => got.filter(x => x.t === t), last: t => got.filter(x => x.t === t).at(-1) };
  ws.onmessage = e => got.push(JSON.parse(e.data)); ws.onclose = e => { closed = e.code || 1; }; ws.onerror = () => {};
  for (let i = 0; i < 100 && !got.length && !closed; i++) await sleep(5);
  c.nonce = got[0]?.nonce; if (o.raw) return c;
  const said = Buffer.concat([Buffer.from(`docked-meet-v1|${o.host || '127.0.0.1'}|`), Buffer.from(o.nonce || c.nonce, 'base64'), Buffer.from(o.key || p.key)]);
  const hk = await wc.subtle.importKey('raw', o.circle || circle, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  c.auth = { t: 'auth', key: b64(o.key || p.key), sig: b64(new Uint8Array(await wc.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, p.k.privateKey, said))), mac: b64(new Uint8Array(await wc.subtle.sign('HMAC', hk, said))) };
  if (o.late) clock += LIMITS.authMs + 1; c.send(c.auth); await sleep(40); return c;
}
const A = await person(), B = await person(), C = await person(), D = await person();
ok(/^[0-9A-HJKMNP-TV-Z]{16}$/.test(A.id) && A.id !== B.id, 'code shape');
// who gets in
let a = await connect(A); ok(a.last('ready')?.id === A.id, 'right key and circle: in');
for (const [o, m] of [[{ circle: new Uint8Array(32) }, 'wrong circle key'], [{ key: B.key }, 'someone else\'s public key'], [{ nonce: b64(randomBytes(32)) }, 'an old answer'], [{ host: 'elsewhere.example' }, 'an answer for another server'], [{ late: 1 }, 'too slow']]) { const x = await connect(D, o); ok(x.closed && !x.last('ready'), m + ': refused'); }
{ const x = await connect(D, { raw: 1 }); x.send({ t: 'watch', ids: [] }); await sleep(30); ok(x.closed, 'talking before proving: closed'); }
{ const x = await connect(D, { raw: 1 }); x.send('not json'); await sleep(30); ok(x.closed, 'nonsense: closed'); }
{ const x = await connect(D, { raw: 1 }); x.send({ t: 'auth', key: 1, sig: {}, mac: null }); await sleep(30); ok(x.closed, 'bad auth types: closed'); }
{ const x = await connect(D, { raw: 1 }); clock += LIMITS.authMs + 1; s.meeting.sweep(); await sleep(30); ok(x.closed, 'a silent connection is swept'); }
{ const d = await connect(D); d.send(d.auth); await sleep(30); ok(d.closed, 'auth twice: closed'); }
// friends see each other only when both added
const b = await connect(B), c = await connect(C);
a.send({ t: 'watch', ids: [B.id, C.id] }); await sleep(30); ok(!a.of('peer').length && !b.of('peer').length, 'one-sided: nobody sees anybody');
a.send({ t: 'send', to: B.id, body: 'x' }); await sleep(30); ok(!b.of('from').length, 'one-sided: no notes');
b.send({ t: 'watch', ids: [A.id] }); await sleep(30); ok(a.last('peer')?.id === B.id && a.last('peer').on && b.last('peer')?.id === A.id, 'both added: both see');
a.send({ t: 'send', to: B.id, body: 'sealed' }); await sleep(30); ok(b.last('from')?.id === A.id && b.last('from').body === 'sealed', 'note arrives, from the proven sender');
a.send({ t: 'send', to: B.id, body: 'sealed', id: C.id, from: C.id }); await sleep(30); ok(b.last('from').id === A.id, 'sender cannot be faked');
ok(!c.of('from').length && !c.of('peer').length, 'a third person sees nothing');
a.send({ t: 'state', ready: true }); await sleep(30); ok(b.last('peer').ready === true && !c.of('peer').length, 'ready shows to friends only');
// requests
c.send({ t: 'request', to: A.id, name: '  Cara‮\n\u0007!  ' }); await sleep(30); ok(a.last('request')?.from === C.id && a.last('request').name === 'Cara!', 'request arrives, name cleaned');
ok(c.last('asked')?.to === A.id, 'asked'); c.send({ t: 'request', to: D.id, name: 'Cara' }); await sleep(30); ok(c.last('asked').to === D.id, 'same answer for someone offline');
c.send({ t: 'request', to: 'ZZZZZZZZZZZZZZZZ', name: 'x' }); await sleep(30); ok(c.last('asked').to === 'ZZZZZZZZZZZZZZZZ', 'same answer for a code nobody has');
let d = await connect(D); ok(d.last('request')?.from === C.id, 'kept for later'); d.send({ t: 'answered', from: C.id }); await sleep(30); d.close(); await sleep(30); d = await connect(D); ok(!d.of('request').length, 'answered: forgotten');
c.send({ t: 'request', to: B.id, name: 'Cara' }); await sleep(30); clock += (LIMITS.requestDays + 1) * 86400000; b.close(); await sleep(30); let b2 = await connect(B); ok(!b2.of('request').length && ![...s.data.keys()].some(k => k.startsWith('r:' + B.id)), 'old requests expire');
for (let i = 0; i < LIMITS.requestsPerHour + 2; i++) d.send({ t: 'request', to: A.id, name: 'D' }); await sleep(80); ok(d.of('slow').length === 2, 'too many requests: slowed');
for (let i = 0; i < LIMITS.pending + 5; i++) await s.data.set('r:' + B.id + ':F' + i, { from: 'F' + i, name: '', until: clock + 1e9 });
c.send({ t: 'request', to: B.id, name: 'late' }); await sleep(40); ok(!s.data.has('r:' + B.id + ':' + C.id), 'a full inbox takes no more');
// leaving
ok(a.last('peer').on === false, 'friend left: told'); b2.send({ t: 'watch', ids: [A.id] }); await sleep(30); ok(a.last('peer').on === true, 'friend back: told');
a.send({ t: 'watch', ids: [] }); await sleep(30); ok(b2.last('peer').on === false, 'removed: friend sees offline'); b2.send({ t: 'send', to: A.id, body: 'x' }); await sleep(30); ok(!a.of('from').length, 'removed: no notes');
// relay passes
a.send({ t: 'turn' }); await sleep(30); ok(a.last('turn').servers === null && !turns, 'no friend ready: no relay pass');
a.send({ t: 'watch', ids: [B.id] }); b2.send({ t: 'state', ready: true }); a.send({ t: 'state', ready: true }); await sleep(30); a.send({ t: 'turn' }); await sleep(30); ok(a.last('turn').servers?.username === 'u' && turns === 1, 'friend ready: relay pass');
for (let i = 0; i < LIMITS.turnPerHour + 3; i++) a.send({ t: 'turn' }); await sleep(80); ok(turns === LIMITS.turnPerHour, 'relay passes per hour are limited');
await s.data.set('d:' + new Date(clock).toISOString().slice(0, 10), LIMITS.turnPerDay); b2.send({ t: 'turn' }); await sleep(30); ok(b2.last('turn').servers === null, 'and per day for everyone');
// the same player twice, limits, odd input
const a2 = await connect(A); ok(a.closed === 4001 && a2.last('ready'), 'newest copy wins');
for (const [m, n] of [[{ t: 'watch', ids: Array(33).fill(B.id) }, 'too many friends'], [{ t: 'watch', ids: ['nope'] }, 'a bad code'], [{ t: 'watch' }, 'no list'], [{ t: 'send', to: B.id, body: 'x'.repeat(LIMITS.body + 1) }, 'a note too long'], [{ t: 'state', ready: 1 }, 'a bad state'], [{ t: 'boom' }, 'an unknown message'], ['[]', 'a list'], ['x'.repeat(LIMITS.message + 1), 'a huge message'], [{ t: 'request', to: C.id }, 'asking oneself']]) { const x = await connect(C); x.send(m); await sleep(30); ok(x.closed, n + ': closed'); }
{ const x = await connect(C); for (let i = 0; i < LIMITS.perMinute + 5; i++) x.send({ t: 'ping' }); await sleep(120); ok(!x.closed && x.of('pong').length <= LIMITS.perMinute, 'too much: ignored, not thrown out'); for (let i = 0; i < LIMITS.perMinute * 4; i++) x.send({ t: 'ping' }); await sleep(200); ok(x.closed, 'a flood: closed'); }
{ clock += 7200000; const n = LIMITS.unproven + 30, w = []; for (let i = 0; i < n; i++) w.push(new WebSocket(`ws://127.0.0.1:${s.port}/meet`)); await sleep(300); const p = await person(), x = await connect(p); ok(x.last('ready'), 'silent connections cannot lock a player out'); for (const y of w) y.close(); await sleep(100); }
{ const fake = { att: null, sent: [], send(t) { this.sent.push(t); }, close(c) { this.closed = c; } }, many = []; const M = s.meeting, real = M.sockets; M.sockets = () => many; for (let i = 0; i < LIMITS.perPlace + 3; i++) { const f = { ...fake, sent: [], att: null, closed: 0 }; many.push(f); M.open(f, '198.51.100.7'); } ok(many.filter(f => f.closed).length === 3, 'one place may hold only so many'); M.sockets = real; }
{ for (let i = 0; i < LIMITS.held; i++) s.data.set('r:ZZZZZZZZZZZZZZZZ:X' + i, { from: 'X', name: '', until: clock + 1e9 }); const p = await person(), q = await person(), x = await connect(p); x.send({ t: 'request', to: q.id, name: 'x' }); await sleep(40); ok(!s.data.has('r:' + q.id + ':' + p.id) && x.last('asked'), 'stored requests are limited in all'); }
ok(cleanName('a'.repeat(99)).length === 24 && cleanName(5) === '' && cleanName('é') === 'é', 'names');
ok([...s.data.keys()].every(k => /^[rd]:/.test(k)), 'nothing else is stored');
console.log(`meeting point: ${pass} passed, ${fail} failed`); s.stop(); process.exit(fail ? 1 : 0);
