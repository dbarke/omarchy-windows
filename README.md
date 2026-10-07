# Window search

Type to find an open window and jump to it, for [Omarchy](https://omarchy.org/).

A small search box over the focused monitor lists every open window, most
recently used first, with the previous one already selected, so `Super+.`
`Enter` flips back like Alt+Tab. Typing filters on the window title, the app
and the workspace; every word has to match one of them, and fuzzy matches
(`gh` for GitHub) count too.

| Key | Does |
|---|---|
| type | Filter |
| `↑` / `↓`, `Tab`, `Ctrl+N` / `Ctrl+P`, `Ctrl+J` / `Ctrl+K` | Select |
| `Enter`, click | Go to the window, wherever it is |
| `Shift+Enter`, Shift+click | Bring it to the workspace you are on, then focus it |
| `Esc`, click outside | Close |

Workspaces show by name, so a scratchpad window says `scratchpad`. Edge and
Chrome web apps are named after their site when no desktop entry claims them.

## Install

```bash
omarchy plugin add https://github.com/dbarke/omarchy-windows --enable
```

Then bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + PERIOD", "Search windows", "omarchy-shell shell toggle dbarke.windows")
```

## License

MIT
