# Static replay of yabai osax hex_find_seq (macOS 26 arm64 patterns) against a Dock binary on disk.
import sys, re, struct, subprocess
dock = sys.argv[1]
pats = {
 'dock_spaces': (0x30000, "?8 ?? ?? ?? 08 ?? ?? 91 00 01 40 F9 E2 03 13 AA ?? ?? ?? 94 ?? ?? ?? ?? 08"),
 'dppm': (0x70000, "?? ?? 00 ?? 08 ?? ?? 91 00 01 40 F9 E2 03 16 AA E3 03 19 AA ?? ?? ?? 94"),
 'fix_animation': (0x250000, "00 10 6A 1E A8 ?? ?? D1 ?? 01 ?? F8"),
 'add_space(26.4+)': (0x250000, "7F 23 03 D5 E1 03 1E AA ?? ?? ?? 97 FE 03 01 AA FD 7B 05 A9 FD 43 01 91 F3 03 14 AA F5 03"),
 'remove_space': (0x1e0000, "7F 23 03 D5 FF ?? ?? D1 FC ?? ?? A9 FA ?? ?? A9 F8 ?? ?? A9 F6 ?? ?? A9 F4 ?? ?? A9 FD ?? ?? A9 FD ?? ?? 91 ?? 03 03 AA F5 03 02 AA F4 03 01 AA"),
 'move_space': (0x1c0000, "7F 23 03 D5 E3 03 1E AA ?? ?? ?? 97 FE 03 03 AA FD 7B ?? A9 FD ?? ?? 91 F6 03 14 AA"),
 'set_front_window': (0x10000, "21 ?? ?? 34 7F 23 03 D5 FF ?? 01 D1 F6 ?? 04 A9 F4 ?? 05 A9 FD ?? 06 A9 FD ?? 01 91"),
}
# locate arm64e slice
out = subprocess.run(['lipo','-detailed_info',dock],capture_output=True,text=True).stdout
off = 0
m = re.search(r"architecture " + (sys.argv[2] if len(sys.argv)>2 else "arm64e") + r"\n.*?offset (\d+)", out, re.S)
if m: off = int(m.group(1))
data = open(dock,'rb').read()
def rx(p):
    parts=[]
    for t in p.split():
        if t=='??': parts.append(b'.')
        elif t[0]=='?': parts.append(b'['+b''.join(re.escape(bytes([h*16+int(t[1],16)])) for h in range(16))+b']')
        else: parts.append(re.escape(bytes([int(t,16)])))
    return re.compile(b''.join(parts), re.S)
for k,(o,p) in pats.items():
    r = rx(p); start = off+o
    first = r.search(data, start, start+0x1286a0+len(p))
    allm = [x.start()-off for x in r.finditer(data, off)]
    print(f"{k:18} window_hit={'0x%x'%(first.start()-off) if first else None} total_matches_in_slice={len(allm)} first5={[hex(a) for a in allm[:5]]}")
