# Alacritty

Minimal terminal config, symlinked to `~/.config/alacritty` by
`linux/arch/bootstrap.sh` (the `dotfiles` stage).

Alacritty reads `$XDG_CONFIG_HOME/alacritty/alacritty.toml`
(`~/.config/alacritty/alacritty.toml` by default) and reloads it on save
(`live_config_reload` defaults to `true`).

## Config

`alacritty.toml`:

```toml
[font]
size = 16.0

[font.normal]
family = "Comic Mono"
```

`Comic Mono` comes from the bootstrap `fonts` stage. If Alacritty warns that
the family is missing, install the font and refresh the cache:

```bash
fc-cache -f
```

## Common additions

Add sections at the top level. For example:

```toml
[window]
padding = { x = 10, y = 10 }
opacity = 0.95

[scrolling]
history = 10000

[selection]
save_to_clipboard = true

[cursor.style]
shape = "Block"
blinking = "Off"
```

## Test changes

```bash
alacritty --config-file ~/.config/alacritty/alacritty.toml
```

Invalid TOML or unknown keys are reported on startup; run `alacritty -vv` for
more detail.

## Resources

- [Configuration reference](https://alacritty.org/config-alacritty.html)
- [Source code](https://github.com/alacritty/alacritty)
