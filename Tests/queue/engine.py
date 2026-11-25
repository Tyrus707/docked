#!/usr/bin/python3
# Stand-in for the engine: reports like it, makes a build folder and an app. What the dump says decides how it goes.
import json, os, plistlib, re, shutil, signal, subprocess, sys, time
if '-I' in sys.argv[:2] or '--help' in sys.argv: sys.exit(0)   # Docked's check of the Python tools, and of a new engine
root = os.environ['DOCKSIDE_ROOT']; a = sys.argv; src = a[a.index('--progress') - 3]; work = a[a.index('--work-dir') + 1]
def say(**k): print(json.dumps(k), flush=True)
def log(s): open(root + '/engine.log', 'a').write(s + '\n')
f = next(n for n in os.listdir(src) if n.endswith('.nsp')); tid = re.search(r'\[([0-9A-F]{16})\]', f).group(1); mode = open(os.path.join(src, f)).read(); name = f.split(' [')[0]
signal.signal(signal.SIGTERM, lambda *_: (os.path.exists(root + '/busy') and os.remove(root + '/busy'), sys.exit(143)))
if os.path.exists(root + '/busy'): log('overlap')
open(root + '/busy', 'w').close(); log('start ' + tid); os.makedirs(work + '/extract', exist_ok=True); open(work + '/extract/x', 'w').write('y' * 5000)
app = os.path.join(root, 'Games', name + '.app'); say(ev='game', title_id=tid, name=name, out=app); say(ev='stage', k=1, n=2, name='Mac shaders'); time.sleep(3 if mode == 'slow' else 0.6)
if mode == 'fail': say(ev='say', msg='[RED] broken on purpose'); os.remove(root + '/busy'); sys.exit(1)
if '--prepare-xcode' in a:
    p = work + '/xcode/DmIOS.xcodeproj'; w = a[a.index('--xcode-workspace') + 1]; old = os.path.exists(p + '/project.pbxproj')
    log('xcode ' + (a[a.index('--bundle-id') + 1] if '--bundle-id' in a else 'kept' if old else 'none'))
    if mode != 'noapp':
        os.makedirs(p, exist_ok=True); open(p + '/project.pbxproj', 'w').write('x'); os.makedirs(w, exist_ok=True); c = w + '/contents.xcworkspacedata'; s = open(c).read() if os.path.exists(c) else '<Workspace version="1.0"></Workspace>'
        if p not in s: open(c, 'w').write(s.replace('</Workspace>', '<Group location="container:" name="%s"><FileRef location="absolute:%s"/></Group></Workspace>' % (name, os.path.realpath(p))))
    say(ev='stage_end', k=1, name='Mac shaders', ok=True); os.remove(root + '/busy'); log('end ' + tid); sys.exit(0)
if '-o' in a:
    if mode != 'noapp': open(a[a.index('-o') + 1], 'wb').write(b'PK\x03\x04' + (b'not an app' if mode == 'tiny' else bytes(9000)))
    log('phone ' + a[a.index('--platform') + 1]); say(ev='stage_end', k=1, name='Mac shaders', ok=True); os.remove(root + '/busy'); log('end ' + tid); sys.exit(0)
os.makedirs(app + '/Contents/MacOS', exist_ok=True); shutil.copy('/usr/bin/true', app + '/Contents/MacOS/dmhost'); os.chmod(app + '/Contents/MacOS/dmhost', 0o755)
plistlib.dump({'DMTitleID': tid, 'CFBundleName': name, 'CFBundleExecutable': 'dmhost', 'CFBundleShortVersionString': '1.0.0', 'LSMinimumSystemVersion': '13.0'}, open(app + '/Contents/Info.plist', 'wb'))
once = mode == 'flaky' and not os.path.exists(root + '/flaky-' + tid)   # unsigned the first time only
if once: open(root + '/flaky-' + tid, 'w').close()
if mode != 'unsigned' and not once: subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', app], check=True, capture_output=True)   # as the real engine signs its apps
if mode == 'warn': say(ev='stage_end', k=1, name='Pipeline archive', ok=True, warn=True, summary='failed, the app is packed without one')
if mode == 'linked' and not os.path.lexists(app + '/Contents/msl'): os.symlink(work + '/extract', app + '/Contents/msl')
open(app + '.key', 'w').write('k'); say(ev='stage_end', k=1, name='Mac shaders', ok=True); os.remove(root + '/busy'); log('end ' + tid)
