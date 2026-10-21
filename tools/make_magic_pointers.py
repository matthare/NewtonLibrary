#!/usr/bin/env python3
"""Makes NewtonLibrary/Package/MagicPointers.swift, the names of the Newton OS 2.1
system objects ("magic pointers"), from the NewtonScript constants file that was
extracted from the Einstein emulator's source for Newton Unlock.

    python3 tools/make_magic_pointers.py
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', '..', 'NewtonUnlockNTK', 'prelude', 'newton_defs.ns')
OUT = os.path.join(HERE, '..', 'NewtonLibrary', 'Package', 'MagicPointers.swift')

src = open(SRC).read()
items = sorted({int(n): name for name, n in re.findall(r'constant (\w+) := @(\d+);', src)}.items())
out = ['// Names of the Newton OS 2.1 system objects ("magic pointers") that packages',
       '// refer to by number, e.g. @157 is protoApp. Extracted from the Einstein',
       '// emulator source (Toolkit/TToolkitPrototypes.cpp, Copyright Paul Guyot and',
       '// Matthias Melcher, GPL v2) by tools/make_magic_pointers.py -- do not edit by hand.', '',
       'enum MagicPointers {', '    static let names: [Int: String] = [']
out += ['        %d: "%s",' % (n, name) for n, name in items]
out += ['    ]', '}', '']
open(OUT, 'w').write('\n'.join(out))
print('wrote %d names to %s' % (len(items), OUT))
