# Configuring fonts

Font setup for Arch Linux with i3. Covers font packages, i3 window titles,
i3bar, the system `sans-serif` alias, and application-specific overrides.

## 1. Install fonts

```bash
sudo pacman -S --needed fontconfig noto-fonts ttf-dejavu
```

- `fontconfig` is usually already installed as a dependency.
- `noto-fonts` provides Noto Sans, which includes Vietnamese glyphs.
- `ttf-dejavu` is a broad fallback font.

Optional packages: `noto-fonts-emoji` for color emoji and `noto-fonts-cjk` for
Chinese, Japanese, and Korean text.

Verify the fonts are visible:

```bash
fc-match "Noto Sans"
fc-list :lang=vi family | sort -u
```

Package installs refresh the font cache automatically. Run `fc-cache -f` after
adding fonts manually under `~/.local/share/fonts/`.

## 2. i3 window titles

Edit `~/.config/i3/config` and set the global font:

```text
font pango:Noto Sans 10
```

This font is used for window titles. It is also used by i3bar unless the `bar`
block sets its own font. The Pango syntax is:

```text
font pango:<family list> [<style options>] <size>
```

A comma-separated family list provides fallbacks:

```text
font pango:Noto Sans, DejaVu Sans 10
```

## 3. i3bar

i3status prints plain text; i3bar renders it. To use a font different from the
global one, add `font` to the `bar` block:

```text
bar {
    position top
    status_command i3status
    font pango:Noto Sans 10
}
```

Third-party bars such as Polybar use their own font settings.

## 4. System `sans-serif` alias

Create a per-user Fontconfig file:

```bash
mkdir -p ~/.config/fontconfig
$EDITOR ~/.config/fontconfig/fonts.conf
```

Add:

```xml
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans</family>
    </prefer>
  </alias>
</fontconfig>
```

This only changes what applications get when they request the generic
`sans-serif` family. Applications that request a specific family are not
affected.

## 5. Apply changes

```bash
fc-cache -f
fc-match sans-serif
i3-msg reload
```

`fc-match sans-serif` should report Noto Sans. Fontconfig changes are read by
applications at startup, so restart open applications to see them.
`i3-msg reload` reloads the i3 configuration; `i3-msg restart` restarts i3
and its bar.

## 6. Application-specific fonts

| Target | File | Setting |
| --- | --- | --- |
| i3 window titles | `~/.config/i3/config` | `font pango:Noto Sans 10` |
| i3bar | `~/.config/i3/config` (`bar` block) | `font pango:Noto Sans 10` |
| Rofi | `~/.config/rofi/config.rasi` | `window { font: "Noto Sans 10"; }` |
| GTK 3 | `~/.config/gtk-3.0/settings.ini` | `gtk-font-name=Noto Sans 10` |
| GTK 4 | `~/.config/gtk-4.0/settings.ini` | `gtk-font-name=Noto Sans 10` |
| kitty | `~/.config/kitty/kitty.conf` | `font_family Noto Sans Mono` |
| Alacritty | `~/.config/alacritty/alacritty.toml` | `[font.normal]` `family = "Noto Sans Mono"` |

Terminal emulators need a monospaced family. `Noto Sans Mono` is included in
`noto-fonts`; use any installed monospaced family instead if preferred.

GTK `settings.ini` files need a `[Settings]` section:

```ini
[Settings]
gtk-font-name=Noto Sans 10
```

GNOME and libadwaita applications may prefer the GSettings value, which
overrides `settings.ini`:

```bash
gsettings set org.gnome.desktop.interface font-name 'Noto Sans 10'
```

Test a Rofi font without editing the config:

```bash
rofi -theme-str 'window { font: "Noto Sans 10"; }' -show drun
```

## 7. Verify

```bash
fc-match sans-serif
fc-match "Noto Sans"
fc-list :lang=vi family | sort -u
```

Expected: the first two commands report a Noto Sans family, and the third lists
fonts that cover Vietnamese.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| i3 falls back to another font | Family name not matched | Run `fc-match "Noto Sans"` and use the reported family name |
| System alias has no effect | Application requests a specific family | Set the font in that application's config |
| GTK app ignores `settings.ini` | GSettings overrides it | Set `org.gnome.desktop.interface font-name` |
| Rofi font unchanged | Config or theme overrides it | Inspect `rofi -dump-config` and `rofi -dump-theme` |
| i3bar text unchanged | Bar uses a different font | Set `font` inside the `bar` block |
| New font not listed | Cache not refreshed | Run `fc-cache -f`, then restart the application |

## References

- [ArchWiki: Fonts](https://wiki.archlinux.org/title/Fonts)
- [ArchWiki: Font configuration](https://wiki.archlinux.org/title/Font_configuration)
- [i3 User's Guide: Fonts](https://i3wm.org/docs/userguide.html#_fonts)
- [i3 User's Guide: Bar configuration](https://i3wm.org/docs/userguide.html#_configuring_i3bar)
- [rofi-theme(5)](https://man.archlinux.org/man/rofi-theme.5)
- [GTK3: GtkSettings:gtk-font-name](https://docs.gtk.org/gtk3/property.Settings.gtk-font-name.html)
- [GTK4: GtkSettings:gtk-font-name](https://docs.gtk.org/gtk4/property.Settings.gtk-font-name.html)
- [fonts-conf(5)](https://man.archlinux.org/man/fonts-conf.5)
