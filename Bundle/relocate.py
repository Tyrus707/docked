# relocate.py <file> <lib folder> <how the file refers to that folder>: copy every Homebrew library a program uses
# into one folder and point the copies at each other, so it runs on a Mac without Homebrew.
import os, re, shutil, subprocess, sys
run = lambda *a: subprocess.run(a, check=True, capture_output=True, text=True).stdout
SYSTEM = ('/usr/lib/', '/System/')
def deps(f): return [m[1] for m in re.finditer(r'^\t(\S+) \(', run('otool', '-L', f), re.M)]
def rpaths(f): return re.findall(r'cmd LC_RPATH.*?path (\S+)', run('otool', '-l', f), re.S)
def find(dep, origin):   # origin: the original file, which @rpath and @loader_path are relative to
    d = os.path.dirname(os.path.realpath(origin))
    sub = lambda p: p.replace('@loader_path', d).replace('@executable_path', d)
    for c in ([os.path.join(sub(r), dep[7:]) for r in rpaths(origin)] + [os.path.join(d, dep[7:]), os.path.join(d, '../lib', dep[7:])] if dep.startswith('@rpath/') else [sub(dep)]):
        if os.path.exists(c): return os.path.realpath(c)
    raise SystemExit(f'{origin}: {dep} not found')
def fix(f, origin, libs, prefix, own=None):
    for dep in deps(f):
        if dep.startswith(SYSTEM) or os.path.basename(dep) == own: continue
        src, name = find(dep, origin), os.path.basename(dep)
        to = os.path.join(libs, name)
        if not os.path.exists(to):
            os.makedirs(libs, exist_ok=True); shutil.copy(src, to); os.chmod(to, 0o755)
            run('install_name_tool', '-id', '@loader_path/' + name, to)
            fix(to, src, libs, '@loader_path', name)
        run('install_name_tool', '-change', dep, f'{prefix}/{name}', f)
    run('codesign', '--force', '--sign', '-', f)
f, origin, libs, prefix = sys.argv[1:5]
fix(f, origin, libs, prefix, sys.argv[5] if len(sys.argv) > 5 else None)
