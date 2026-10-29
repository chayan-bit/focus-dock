# usage: strxref.py disasm.txt cstrings.txt regex  -> functions referencing matching cstrings via adrp+add
import sys, re
dis, cs, pat = sys.argv[1], sys.argv[2], re.compile(sys.argv[3])
strings = {}
for l in open(cs, encoding='latin-1'):
    m = re.match(r'(0x[0-9A-Fa-f]+) "(.*)"$', l.rstrip('\n'))
    if m and pat.search(m.group(2)): strings[int(m.group(1),16)] = m.group(2)
func=None; page={}
for l in open(dis, encoding='latin-1'):
    if l and not l.startswith('0x') and l.rstrip().endswith(':'): func=l.rstrip()[:-1]; page={}; continue
    m = re.match(r'(0x[0-9A-F]+)\s+adrp\s+(x\d+), .*; (0x[0-9a-f]+)', l)
    if m: page[m.group(2)] = int(m.group(3),16); continue
    m = re.match(r'(0x[0-9A-F]+)\s+add\s+(x\d+), (x\d+), #(0x[0-9a-f]+)', l)
    if m and m.group(3) in page:
        a = page[m.group(3)] + int(m.group(4),16)
        if a in strings: print(f'{m.group(1)} {func} -> "{strings[a]}"')
