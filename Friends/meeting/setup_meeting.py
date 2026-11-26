#!/usr/bin/env python3
"""Puts your meeting point on your own Cloudflare account, and saves your friends pass (friends.cfg) where Docked and every converted game look for it. Run it yourself, in Terminal.
It asks for an API token, which is not shown, not saved, and sent only to Cloudflare. Running it again updates the meeting point and keeps its keys.
  python3 -I setup_meeting.py            set up or update
  python3 -I setup_meeting.py --new-key  replace the shared key (everyone then needs a new patcher)"""
import base64, getpass, json, os, secrets, ssl, sys, urllib.error, urllib.request
API = os.environ.get('MEETING_TEST_API', ''); API = API if API.startswith('http://127.0.0.1:') else 'https://api.cloudflare.com/client/v4'
HERE = os.path.dirname(os.path.abspath(__file__)); NAME = 'docked-meeting'; OUT = os.environ.get('MEETING_TEST_OUT') or os.path.expanduser('~/Library/Application Support/Docked/Friends')
CFG = OUT + '/friends.cfg'
class No(Exception): pass
def call(token, method, path, body=None, ctype='application/json', missing_ok=False):
    data = body if isinstance(body, bytes) else json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(API + path, data=data, method=method, headers={'Authorization': 'Bearer ' + token, 'User-Agent': 'docked-meeting-setup', **({'Content-Type': ctype} if data is not None else {})})
    try:
        with urllib.request.urlopen(r, timeout=30) as f: j = json.load(f)
    except urllib.error.HTTPError as e:
        if missing_ok and e.code == 404: return None
        try: m = '; '.join(x.get('message', '') for x in json.load(e).get('errors', []))
        except Exception: m = ''
        raise No({401: 'Cloudflare did not accept that token.', 403: 'That token lacks a permission for this step (%s).' % path.split('/')[-1]}.get(e.code, f'Cloudflare answered {e.code}.') + (' ' + m if m else ''))
    except urllib.error.URLError as e: raise No(f'Cloudflare could not be reached ({e.reason}).')
    return j.get('result', j)
def multipart(parts):
    b = secrets.token_hex(16); o = b''
    for name, fn, ct, d in parts: o += (f'--{b}\r\nContent-Disposition: form-data; name="{name}"' + (f'; filename="{fn}"' if fn else '') + f'\r\nContent-Type: {ct}\r\n\r\n').encode() + d + b'\r\n'
    return o + f'--{b}--\r\n'.encode(), 'multipart/form-data; boundary=' + b
def main():
    token = getpass.getpass('Cloudflare API token (hidden): ').strip()
    if not token: raise No('No token given.')
    acc = call(token, 'GET', '/accounts')
    if not acc: raise No('That token sees no account.')
    a = acc[0]
    if len(acc) > 1:
        for i, x in enumerate(acc): print(f'  {i + 1}. {x["name"]}')
        a = acc[int(input('Which account? ')) - 1]
    base = '/accounts/' + a['id']; circle = None
    if os.path.exists(CFG) and '--new-key' not in sys.argv:
        for l in open(CFG):
            if l.startswith('circle='): circle = l[7:].strip()
    if circle and len(base64.b64decode(circle)) != 32: raise No('The saved shared key is damaged. Use --new-key to make another.')
    circle = circle or base64.b64encode(secrets.token_bytes(32)).decode()
    sub = call(token, 'GET', base + '/workers/subdomain', missing_ok=True); sub = sub and sub.get('subdomain')
    if not sub: sub = call(token, 'PUT', base + '/workers/subdomain', {'subdomain': 'docked-' + secrets.token_hex(5)})['subdomain']
    host = f'{NAME}.{sub}.workers.dev'
    there = any(s.get('id') == NAME for s in call(token, 'GET', base + '/workers/scripts'))
    bind = [{'type': 'durable_object_namespace', 'name': 'MEETING', 'class_name': 'MeetingPoint'}, {'type': 'plain_text', 'name': 'MEET_HOST', 'text': host}, {'type': 'secret_text', 'name': 'CIRCLE_KEY', 'text': circle}]
    had = {b.get('name') for b in (call(token, 'GET', f'{base}/workers/scripts/{NAME}/bindings', missing_ok=True) or [])} if there else set(); relay = {'TURN_KEY_ID', 'TURN_TOKEN'} <= had
    if not relay:
        try: t = call(token, 'POST', base + '/calls/turn_keys', {'name': NAME}); bind += [{'type': 'plain_text', 'name': 'TURN_KEY_ID', 'text': t['uid']}, {'type': 'secret_text', 'name': 'TURN_TOKEN', 'text': t.get('secret') or t['key']}]; relay = True
        except (No, KeyError) as e: print(f'Relay not set up, so friends who cannot connect directly will not be able to play: {e}')
    meta = {'main_module': 'worker.js', 'compatibility_date': '2026-06-01', 'bindings': bind, 'keep_bindings': ['secret_text', 'plain_text'], 'observability': {'enabled': False}}
    if not there: meta['migrations'] = {'new_tag': 'v1', 'new_sqlite_classes': ['MeetingPoint']}
    js = 'application/javascript+module'; parts = [('metadata', None, 'application/json', json.dumps(meta).encode())] + [(f, f, js, open(f'{HERE}/{f}', 'rb').read()) for f in ('worker.js', 'core.js')]
    body, ct = multipart(parts); call(token, 'PUT', f'{base}/workers/scripts/{NAME}', body, ct); call(token, 'POST', f'{base}/workers/scripts/{NAME}/subdomain', {'enabled': True, 'previews_enabled': False})
    os.makedirs(OUT, mode=0o700, exist_ok=True); os.chmod(OUT, 0o700); t = CFG + '.new'
    if os.path.exists(t): os.remove(t)
    with os.fdopen(os.open(t, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as f: f.write(f'meet=wss://{host}/meet\ncircle={circle}\n')
    os.replace(t, CFG); print(f'Done. Your meeting point is up, {"with" if relay else "without"} a relay. You can delete the API token at Cloudflare now.')
try: main()
except (No, ValueError, IndexError) as e: print('Not done:', e); sys.exit(1)
except KeyboardInterrupt: print('\nStopped.'); sys.exit(1)
