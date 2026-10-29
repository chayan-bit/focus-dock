# REA probes

Read-only helpers behind [docs/research/rea-macos-ui.md](../../docs/research/rea-macos-ui.md); none of them inject code or call a setter.
`probe.m` checks that private symbols exist via `dlsym` and calls getters only: `clang -fobjc-arc -framework Foundation -framework CoreGraphics probe.m -o probe && ./probe SLSMainConnectionID ...`.
`sa_scan.py <Dock binary> [arm64e|arm64e.x1]` replays yabai's macOS 26 scripting-addition byte patterns (yabai, MIT) over a Dock slice to see which still match.
`strxref.py <disasm.txt> <cstrings.txt> <regex>` lists functions that load a matching C string via `adrp`+`add`, from `dyld_info -disassemble` and string dumps you generate locally (never commit dumps).
