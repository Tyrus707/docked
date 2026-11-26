// Test only: the meeting point on 127.0.0.1 with a minimal WebSocket server, no packages. node test/server.mjs <port> <circle key base64> [turn user:credential]
import http from 'node:http';
import { createHash } from 'node:crypto';
import { Meeting } from '../core.js';
export function serve(port, circleKey, { turn = null, now, host = '127.0.0.1' } = {}) {
  const socks = new Set(), data = new Map();
  const store = { get: async k => data.get(k), put: async (k, v) => { data.set(k, v); }, delete: async k => { data.delete(k); }, list: async p => new Map([...data].filter(([k]) => k.startsWith(p))) };
  const meeting = new Meeting({ store, sockets: () => socks, circleKey, host, turn, ...(now ? { now } : {}) });
  const srv = http.createServer((q, r) => { r.writeHead(404); r.end(); });
  srv.on('upgrade', (req, s) => {
    if (req.url !== '/meet') { s.destroy(); return; }
    s.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + createHash('sha1').update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64') + '\r\n\r\n');
    const frame = (op, p) => { const n = p.length, h = n < 126 ? Buffer.from([0x80 | op, n]) : Buffer.from([0x80 | op, 126, n >> 8, n & 255]); if (!s.destroyed) s.write(Buffer.concat([h, p])); };
    const ws = { att: null, send: t => frame(1, Buffer.from(t)), close(c) { if (!socks.has(ws)) return; frame(8, Buffer.from([c >> 8, c & 255])); s.end(); gone(); } };
    const gone = () => { if (socks.delete(ws)) meeting.close(ws); };
    let buf = Buffer.alloc(0), q = Promise.resolve();
    s.on('data', d => {
      buf = Buffer.concat([buf, d]);
      for (;;) {
        if (buf.length < 2) return; let n = buf[1] & 127, o = 2; if (n === 126) { if (buf.length < 4) return; n = buf.readUInt16BE(2); o = 4; } else if (n === 127) { s.destroy(); return; }
        if (!(buf[1] & 128)) { s.destroy(); return; } if (buf.length < o + 4 + n) return;
        const mask = buf.subarray(o, o + 4), p = Buffer.from(buf.subarray(o + 4, o + 4 + n)); for (let i = 0; i < n; i++) p[i] ^= mask[i & 3];
        const op = buf[0] & 15; buf = buf.subarray(o + 4 + n);
        if (op === 1) q = q.then(() => meeting.message(ws, p.toString())).catch(e => { console.error(e); ws.close(1011); });
        else if (op === 8) { s.end(); gone(); } else if (op === 9) frame(10, p);
      }
    });
    s.on('close', gone); s.on('error', gone); socks.add(ws); meeting.open(ws, req.headers['x-test-place'] || '');
  });
  return new Promise(ok => srv.listen(port, '127.0.0.1', () => ok({ meeting, data, port: srv.address().port, stop: () => { for (const s of [...socks]) s.close(1001); srv.close(); } })));
}
if (process.argv[1]?.endsWith('server.mjs') && process.argv[2]) {
  const [u, c] = (process.argv[4] || '').split(/:(.*)/s);
  const s = await serve(+process.argv[2], new Uint8Array(Buffer.from(process.argv[3], 'base64')), { turn: u ? async () => ({ username: u, credential: c }) : null });
  console.log('meeting point on', s.port);
}
