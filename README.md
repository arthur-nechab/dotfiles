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

## 🚀 Setup

Run this command on a new machine:

```sh
chezmoi init --apply arthur-nechab/dotfiles
```

If chezmoi is not installed yet, this one-liner installs it and then runs the same command:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply arthur-nechab/dotfiles
```

To read the changes before they are applied, leave out `--apply` and run `chezmoi diff`.

The same command gives a different result on each machine. `.chezmoi.toml.tmpl` reads
`/etc/os-release` and sets three values: an OS id, a compositor (`de`) and a shell layer
(`shell`). `.chezmoiignore` uses them to decide which configs each machine receives.

### After the first apply

Two tools need a one-time step. yazi keeps its plugins and flavors out of this repo and pins
them in `package.toml`, so fetch them after the first apply, and again whenever that file
changes:

```sh
ya pkg install
```

herdr registers its plugins itself, the two local ones included, and `config.toml` binds their
keys. Link the local plugins once:

```sh
herdr plugin link ~/.config/herdr/lowercase-workspace
herdr plugin link ~/.config/herdr/sidebar
```

## 🧰 Runtime tools (Arch)

The Hyprland and quickshell setup on Arch calls the tools below, and this repo does not install
them. The names are the Arch package names.

| Used for | Packages |
| --- | --- |
| Session | `quickshell`, `hyprland`, `hyprsunset`, `hyprpicker`, `xdg-desktop-portal-gnome`, `dbus`, `systemd` |
| Audio, network, hardware | `wireplumber`, `pipewire`, `brightnessctl`, `iwd`, `bluez-utils`, `iputils`, `cava`, `nvidia-utils`, `udisks2` |
| Screenshot, recording, clipboard, OCR | `grim`, `slurp`, `swappy`, `wf-recorder`, `wl-clipboard`, `clipse`, `tesseract` |
| Launcher calculator | `libqalculate` |
| Apps opened from the bar and keybinds | `ghostty`, `nautilus`, `btop`, `yazi`, `bluetuith`, `impala`, `pwvucontrol`, `cloudflare-speed-cli` |
| Notifications, desktop glue, scripts | `libnotify`, `xdg-utils`, `gtk3`, `desktop-file-utils`, `python-pillow`, `curl`, `jq` |

## 📂 XDG Directories

The config follows the
[XDG Base Directory spec](https://specifications.freedesktop.org/basedir-spec/latest/), so `$HOME`
stays clean, and `dot_zshenv.tmpl` exports the XDG variables.

zsh reads `~/.zshenv` only from `$HOME`, which makes it the one dotfile that stays there. That
file sets `ZDOTDIR` to `~/.config/zsh`, and this moves `.zshrc` out of `$HOME`.

## 🌳 Layout

Each tool has its own directory under `dot_config/`, which becomes `~/.config/`. A `dot_` prefix
gives a leading `.`, `private_` sets mode 0700, and a `.tmpl` suffix marks a template.
`.chezmoiignore` decides which directories a machine receives.

`dot_config/hypr/` holds Hyprland. Its shell is in `dot_config/quickshell/` or
`dot_config/noctalia/`, depending on the machine. `dot_config/scripts/` holds the scripts that the
bar and the keybinds call.
