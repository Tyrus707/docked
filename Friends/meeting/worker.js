// Cloudflare adapter: one Durable Object holds everyone's connection. Secrets: CIRCLE_KEY (base64, 32 bytes), TURN_KEY_ID and TURN_TOKEN (both optional: no relay without them).
import { DurableObject } from 'cloudflare:workers';
import { Meeting } from './core.js';

export default {
  async fetch(req, env) {
    const u = new URL(req.url);
    if (u.pathname !== '/meet' || req.headers.get('Upgrade') !== 'websocket' || req.headers.has('Origin')) return new Response('Not found', { status: 404 });   // games send no Origin; web pages always do
    return env.MEETING.get(env.MEETING.idFromName('main')).fetch(req);
  },
};

class Socket {
  constructor(ws) { this.ws = ws; }
  get att() { try { return this.ws.deserializeAttachment(); } catch { return null; } }
  set att(v) { try { this.ws.serializeAttachment(v); } catch { /* already closed */ } }
  send(t) { try { this.ws.send(t); } catch { /* already closed */ } }
  close(c) { try { this.ws.close(c); } catch { /* already closed */ } }
}

export class MeetingPoint extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.wrapped = new WeakMap();
    const wrap = ws => { let s = this.wrapped.get(ws); if (!s) this.wrapped.set(ws, s = new Socket(ws)); return s; };
    this.wrap = wrap;
    const circleKey = Uint8Array.from(atob(env.CIRCLE_KEY || ''), c => c.charCodeAt(0));
    const turn = env.TURN_KEY_ID && env.TURN_TOKEN ? async ttl => {
      const r = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${env.TURN_KEY_ID}/credentials/generate-ice-servers`, {
        method: 'POST', headers: { Authorization: `Bearer ${env.TURN_TOKEN}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ ttl }), signal: AbortSignal.timeout(5000) });
      if (!r.ok) return null;
      const s = (await r.json())?.iceServers; const list = Array.isArray(s) ? s : s ? [s] : [];
      const g = list.find(x => x?.username && x?.credential);
      return g ? { username: String(g.username), credential: String(g.credential) } : null;
    } : null;
    this.meeting = new Meeting({
      store: { get: k => ctx.storage.get(k), put: (k, v) => ctx.storage.put(k, v), delete: k => ctx.storage.delete(k), list: prefix => ctx.storage.list({ prefix }) },
      sockets: () => ctx.getWebSockets().map(wrap), circleKey, host: env.MEET_HOST, turn });
  }
  async fetch(req) {
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    this.meeting.open(this.wrap(server), req.headers.get('CF-Connecting-IP') || '');
    if (!(await this.ctx.storage.getAlarm())) await this.ctx.storage.setAlarm(Date.now() + 15000);
    return new Response(null, { status: 101, webSocket: client });
  }
  async alarm() { this.meeting.sweep(); if (this.ctx.getWebSockets().some(w => this.wrap(w).att?.nonce)) await this.ctx.storage.setAlarm(Date.now() + 15000); }
  async webSocketMessage(ws, m) { try { await this.meeting.message(this.wrap(ws), m); } catch { this.wrap(ws).close(1011); } }
  async webSocketClose(ws) { this.meeting.close(this.wrap(ws)); }
  async webSocketError(ws) { this.meeting.close(this.wrap(ws)); }
}
