# Third-party material

## Omarchy themes and templates

Source: https://github.com/basecamp/omarchy
Commit: aba49d22cf77b4a8fd1859c721d6bbc6e986a27e
Licence: MIT (below)

What FocusDock takes from it:

- `Themes/<name>/colors.toml`, `neovim.lua` and `btop.theme` for all 23 themes under `themes/`, unchanged.
- `Themes/<name>/preview.jpg`: each theme's `preview.png`, scaled to 480 px wide and re-encoded as JPEG to keep the repo small.
- `Themes/backgrounds.sha256`: SHA-256 of every background still under `themes/*/backgrounds/` at that commit; `scripts/sync-backgrounds.sh` downloads them from that commit and checks them (they are not in this repo).
- `Templates/btop.theme.tpl` and `Templates/neovim.lua.tpl`, unchanged; `Templates/claude.json.tpl` with the theme name changed to "FocusDock".
- `Templates/zed.json.tpl` maps the palette to Zed roles following `default/themed/vscode-theme.json.tpl`.
- Ported behaviour (Swift, no code copied verbatim): the `colors.toml` reader and resolver (`bin/omarchy-theme-color`), the template renderer and its helpers (`bin/omarchy-theme-set-templates`), staging, the git-theme safety rule, the swap and background choice (`bin/omarchy-theme-set`).

```
MIT License

Copyright (c) David Heinemeier Hansson

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
