#!/usr/bin/python3
# Stand-in for the engine: reports like it, makes a build folder and an app. What the dump says decides how it goes.
import json, os, plistlib, re, signal, sys, time
if '-I' in sys.argv[:2]: sys.exit(0)   # Docked's check of the Python tools
root = os.environ['DOCKSIDE_ROOT']; a = sys.argv; src = a[a.index('--progress') - 3]; work = a[a.index('--work-dir') + 1]
def say(**k): print(json.dumps(k), flush=True)
def log(s): open(root + '/engine.log', 'a').write(s + '\n')
f = next(n for n in os.listdir(src) if n.endswith('.nsp')); tid = re.search(r'\[([0-9A-F]{16})\]', f).group(1); mode = open(os.path.join(src, f)).read(); name = f.split(' [')[0]
signal.signal(signal.SIGTERM, lambda *_: (os.path.exists(root + '/busy') and os.remove(root + '/busy'), sys.exit(143)))
if os.path.exists(root + '/busy'): log('overlap')
open(root + '/busy', 'w').close(); log('start ' + tid); os.makedirs(work + '/extract', exist_ok=True); open(work + '/extract/x', 'w').write('y' * 5000)
app = os.path.join(root, 'Games', name + '.app'); say(ev='game', title_id=tid, name=name, out=app); say(ev='stage', k=1, n=2, name='Mac shaders'); time.sleep(3 if mode == 'slow' else 0.6)
if mode == 'fail': say(ev='say', msg='[RED] broken on purpose'); os.remove(root + '/busy'); sys.exit(1)
os.makedirs(app + '/Contents/MacOS', exist_ok=True); open(app + '/Contents/MacOS/dmhost', 'w').write('x'); os.chmod(app + '/Contents/MacOS/dmhost', 0o755)
plistlib.dump({'DMTitleID': tid, 'CFBundleName': name, 'CFBundleShortVersionString': '1.0.0', 'LSMinimumSystemVersion': '13.0'}, open(app + '/Contents/Info.plist', 'wb'))
if mode == 'linked' and not os.path.lexists(app + '/Contents/msl'): os.symlink(work + '/extract', app + '/Contents/msl')
open(app + '.key', 'w').write('k'); say(ev='stage_end', k=1, name='Mac shaders', ok=True); os.remove(root + '/busy'); log('end ' + tid)
