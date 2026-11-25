#!/usr/bin/env python3
# The engine's fingerprint, as Docked takes it (Engine.tree in Sources/Engine.swift), and the difference between two engines.
#   engine_tree.py tree <engine folder>                  prints: <sha256> <number of files>
#   engine_tree.py delta <old folder> <new folder> <out>  puts in <out>: engine/ with the new and changed files, engine.removed with the paths that went
# The fingerprint is the SHA-256 of one line per file, sorted by path as bytes: <path> TAB <sha256> TAB <x or -> for an executable. Python's caches and Finder's
# .DS_Store are left out, as Python writes them into the engine when it runs. Anything that is neither a file nor a folder gets a line no download can match.
import hashlib, os, shutil, sys

def skipped(name): return name == '.DS_Store' or name.endswith('.pyc')

def rows(top):
    out = {}
    for here, dirs, files in os.walk(top):
        for d in list(dirs):
            if d == '__pycache__': dirs.remove(d)
            elif os.path.islink(os.path.join(here, d)): out[os.path.relpath(os.path.join(here, d), top)] = '?'; dirs.remove(d)
        for f in files:
            if skipped(f): continue
            p = os.path.join(here, f); rel = os.path.relpath(p, top)
            if os.path.islink(p) or not os.path.isfile(p): out[rel] = '?'; continue
            h = hashlib.sha256()
            with open(p, 'rb') as fh:
                for b in iter(lambda: fh.read(1 << 20), b''): h.update(b)
            out[rel] = h.hexdigest() + '\t' + ('x' if os.stat(p).st_mode & 0o111 else '-')
    return out

def tree(top):
    r = rows(top)
    text = ''.join(f'{k}\t{r[k]}\n' for k in sorted(r, key=lambda k: k.encode()))
    return hashlib.sha256(text.encode()).hexdigest(), len(r)

def delta(old, new, out):
    a, b = rows(old), rows(new)
    if '?' in b.values(): sys.exit('the new engine holds something that is not a plain file')
    os.makedirs(os.path.join(out, 'engine'), exist_ok=True)
    for k in sorted(b):
        if a.get(k) != b[k]:
            d = os.path.join(out, 'engine', k); os.makedirs(os.path.dirname(d), exist_ok=True); shutil.copy2(os.path.join(new, k), d)
    gone = sorted((k for k in a if k not in b), key=lambda k: k.encode())
    with open(os.path.join(out, 'engine.removed'), 'w') as f: f.write(''.join(k + '\n' for k in gone))
    print(sum(1 for k in b if a.get(k) != b[k]), 'changed or new,', len(gone), 'removed')

if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'tree': print(*tree(sys.argv[2]))
    elif len(sys.argv) == 5 and sys.argv[1] == 'delta': delta(*sys.argv[2:])
    else: sys.exit(__doc__ or 'usage: engine_tree.py tree <folder> | delta <old> <new> <out>')
