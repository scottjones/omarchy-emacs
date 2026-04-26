# omarchy-emacs

An Arch package that auto-syncs Emacs to [Omarchy's](https://github.com/basecamp/omarchy) theme and font. A thin integration layer — ships an `omarchy.el`, a single theme file, and a font-change hook. Works with the Wayland-native pgtk Emacs build (`emacs-wayland`).

## What it syncs

- **Theme colors.** Driven from `~/.config/omarchy/current/theme/omarchy-colors.el`, which Omarchy regenerates from a template (shipped by this package as `omarchy-colors.el.tpl`) every time you run `omarchy-theme-set`. The Emacs theme covers core faces, font-lock, mode-line, line numbers, completion, links, errors/warnings, org-mode, and diff/ediff. See `config/themes/omarchy-theme.el`.
- **Font family.** Read from `~/.config/waybar/style.css` — the same source `omarchy-font-set` writes to.
- **Font size.** Read from your default terminal's config:
  - alacritty — `~/.config/alacritty/alacritty.toml`, `[font] size`
  - kitty — `~/.config/kitty/kitty.conf`, `font_size`
  - ghostty — `~/.config/ghostty/config`, `font-size`

  Default terminal is resolved via `~/.config/xdg-terminals.list`.
- **No Emacs restart required.** Theme changes are picked up by a file watcher on `~/.config/omarchy/current/theme.name`. Font changes trigger via the `font-set` hook.

## Install

```
yay -S omarchy-emacs
omarchy-install-emacs
```

`omarchy-install-emacs` installs `emacs-wayland`, runs `omarchy-emacs-setup`, and enables the `emacs.service` systemd user unit.

If you have a legacy `~/.emacs` or `~/.emacs.d`, the setup script will warn you and offer to back them up — those paths take precedence over `~/.config/emacs/` and will prevent the integration from loading.

## What gets installed where

| Path | Status |
| --- | --- |
| `~/.config/emacs/init.el` | **Yours** — copied only if missing. Loads `omarchy.el`; add your customizations after the load line. |
| `~/.config/emacs/omarchy.el` | **Managed** — overwritten on every `omarchy-emacs-setup` run. |
| `~/.config/emacs/themes/omarchy-theme.el` | **Managed** — overwritten on every setup run. |
| `~/.config/emacs/shell-bashrc` | **Yours** — rcfile for Emacs `M-x shell`. |
| `~/.config/omarchy/hooks/font-set` | **Managed** while the `omarchy-emacs:managed` marker comment is intact. Remove the marker to keep your own customizations. |
| `~/.config/omarchy/themed/omarchy-colors.el.tpl` | Color template consumed by `omarchy-theme-set`. |

## Customizing

- Add personal config to `~/.config/emacs/init.el` *after* the `(load "omarchy")` line.
- To opt out of the integration without uninstalling, delete that load line — Emacs no longer touches Omarchy state.
- Don't edit `omarchy.el` or `omarchy-theme.el` — they get overwritten.

## Provided commands

- `omarchy-emacs-setup` — idempotent setup; safe to re-run.
- `omarchy-install-emacs` — one-shot installer (used during initial install).
- `omarchy-restart-emacs` — reloads `omarchy.el` and reapplies theme/font in the running daemon. Does *not* restart the daemon.

## Troubleshooting

**Font or theme didn't update.** Run `omarchy-restart-emacs`. If that doesn't help, restart the daemon fully:

```
systemctl --user restart emacs.service
```

**Wrong font size after a `yay -Syu` upgrade.** Most likely cause: a stale `init.el` from before the `omarchy.el` split (pre-1.7). Because `init.el` is user-owned, the package never overwrites it on upgrade. Back yours up and copy the fresh starter over:

```
mv ~/.config/emacs/init.el ~/.config/emacs/init.el.bak
cp /usr/share/omarchy-emacs/config/init.el ~/.config/emacs/init.el
systemctl --user restart emacs.service
```

If you had customizations in the old `init.el`, salvage them from the `.bak` file and paste them after the `(load "omarchy")` line.

**No colors / faces look like default Emacs.** Check that `~/.config/omarchy/current/theme/omarchy-colors.el` exists. If it doesn't, run `omarchy-theme-set <theme>` once to generate it.

**`~/.emacs` or `~/.emacs.d` warning during setup.** Those legacy paths take precedence over `~/.config/emacs/`. Let the setup script back them up, or do it yourself.

## License

MIT — see [LICENSE](LICENSE).

Issues and PRs welcome at the [GitHub repo](https://github.com/scottjones/omarchy-emacs).
