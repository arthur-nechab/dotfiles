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
| Desktop (Arch) | hyprland, waybar, rofi, swaync, hypridle, hyprlock |
| Laptop (Debian) | hyprland, noctalia |
| Theme | gruvbox |

## 🚀 Setup

If chezmoi is not installed, use this command:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply arthur-nechab/dotfiles
```

If chezmoi is already installed (Homebrew, pacman, and others):

```sh
chezmoi init --apply arthur-nechab/dotfiles
```

To inspect the changes before you apply them:

```sh
chezmoi init arthur-nechab/dotfiles
chezmoi diff
chezmoi apply
```

To pull later changes:

```sh
chezmoi update
```

The same command gives a different result on each machine. `.chezmoi.toml.tmpl` reads
`/etc/os-release` and sets three values: an OS id, a compositor (`de`) and a shell layer
(`shell`). `.chezmoiignore` uses them to select the configs.

## 📂 XDG Directories

Everything here follows the [XDG Base Directory
spec](https://specifications.freedesktop.org/basedir-spec/latest/). `$HOME` stays clean, and
config, data, cache and state stay separate. `dot_zshenv.tmpl` exports these variables. zsh
reads that file first:

| Variable | Path | Holds |
| --- | --- | --- |
| `XDG_CONFIG_HOME` | `~/.config` | configuration, the files this repo writes |
| `XDG_DATA_HOME` | `~/.local/share` | application data that must persist |
| `XDG_CACHE_HOME` | `~/.cache` | regenerable cache, safe to delete |
| `XDG_STATE_HOME` | `~/.local/state` | logs, history, runtime state |
| `ZDOTDIR` | `~/.config/zsh` | keeps `.zshrc` out of `$HOME` |

`ZDOTDIR` is the exception. zsh reads `~/.zshenv` only from `$HOME`. Therefore `~/.zshenv` is the
only dotfile in `$HOME`. It exports the other variables and points zsh at `~/.config/zsh`.

## 🌳 Directory structure

```
.
├── .chezmoi.toml.tmpl                  # per-machine values (OS id, compositor, shell) and sourceDir
├── .chezmoiignore                      # the configs each machine does not receive
├── dot_zshenv.tmpl                     # → ~/.zshenv, exports XDG vars and ZDOTDIR
├── private_dot_gnupg/                  # → ~/.gnupg, gpg-agent (0700)
├── Library/                            # → macOS only, VS Code settings
└── dot_config/                         # → ~/.config
    ├── zsh/                            # .zshrc, .zprofile
    ├── ohmyposh/                       # prompt
    ├── ghostty/                        # terminal
    ├── nvim/  zed/                     # editors
    ├── git/                            # neutral git preferences, global gitignore
    ├── yazi/  lazygit/  btop/  herdr/  # TUIs
    ├── fastfetch/                      # system info
    ├── hypr/                           # Hyprland (de = hyprland)
    ├── waybar/  rofi/  swaync/         # modular shell (shell = modular)
    ├── noctalia/                       # noctalia shell (shell = noctalia)
    ├── niri/
    └── scripts/                        # scripts that the bar and the keybinds call
```
