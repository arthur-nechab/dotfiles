# 🏠 dotfiles

**Home sweet ~.** My shell, prompt, editors, terminal, file manager and desktop, kept in sync
across machines with [chezmoi](https://www.chezmoi.io).

| Role | Tools |
| --- | --- |
| Shell + prompt | zsh, oh-my-posh, zsh-autosuggestions, zsh-syntax-highlighting |
| Terminal | ghostty |
| Multiplexer | herdr |
| Editors | nvim (LazyVim), zed, vscode (macOS) |
| Navigation | yazi, eza, bat, fd, ripgrep, fzf, zoxide |
| Git | lazygit |
| System | btop, fastfetch |
| Desktop (Hyprland) | hyprland, waybar, rofi, swaync, hypridle, hyprlock |
| Theme | gruvbox |

## 🚀 Setup

Chezmoi not installed yet, one-liner:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply arthur-nechab/dotfiles
```

Chezmoi already installed (Homebrew, pacman, ...):

```sh
chezmoi init --apply arthur-nechab/dotfiles
```

Cautious install, inspect before touching anything:

```sh
chezmoi init arthur-nechab/dotfiles
chezmoi diff
chezmoi apply
```

To pull later changes:

```sh
chezmoi update
```

The same command gives a different result per machine: `.chezmoi.toml.tmpl` derives an OS id
and a desktop environment from `/etc/os-release`, and `.chezmoiignore` gates each config on
those. The Hyprland desktop only lands on a machine whose desktop is Hyprland, never on a KDE
one, and `Library/` only on macOS.

## 📂 XDG Directories

Everything here follows the [XDG Base Directory
spec](https://specifications.freedesktop.org/basedir-spec/latest/): `$HOME` stays clean, and
config, data, cache and state stay separable. Exported in `dot_zshenv.tmpl`, which zsh reads
before anything else:

| Variable | Path | Holds |
| --- | --- | --- |
| `XDG_CONFIG_HOME` | `~/.config` | configuration, what this repo writes |
| `XDG_DATA_HOME` | `~/.local/share` | application data meant to persist |
| `XDG_CACHE_HOME` | `~/.cache` | regenerable cache, safe to delete |
| `XDG_STATE_HOME` | `~/.local/state` | logs, history, runtime state |
| `ZDOTDIR` | `~/.config/zsh` | keeps `.zshrc` out of `$HOME` |

`ZDOTDIR` is the one that needs a foothold: zsh only reads `~/.zshenv` from `$HOME`, so that file
is the sole dotfile left at the top level, exporting the rest and pointing zsh at `~/.config/zsh`.

## 🌳 Directory structure

```
.
├── .chezmoi.toml.tmpl              # per-machine axes (OS id, desktop) + sourceDir
├── .chezmoiignore                  # which configs each machine does NOT get
├── dot_zshenv.tmpl                 # → ~/.zshenv, exports XDG vars and ZDOTDIR
├── private_dot_gnupg/              # → ~/.gnupg, gpg-agent (0700)
├── Library/                        # → macOS only, VS Code settings
└── dot_config/                     # → ~/.config
    ├── zsh/                        # .zshrc, .zprofile
    ├── ohmyposh/                   # prompt
    ├── ghostty/                    # terminal
    ├── nvim/  zed/                 # editors
    ├── git/                        # global gitignore
    ├── yazi/  lazygit/  btop/  herdr/  # TUIs
    ├── fastfetch/
    ├── hypr/  waybar/  rofi/       # Hyprland desktop
    ├── swaync/
    └── scripts/                    # helpers the bar and keybinds call
```
