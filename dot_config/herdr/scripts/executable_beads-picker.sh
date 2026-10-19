#!/usr/bin/env bash
# Pick a bead of the focused pane's repo: the preview shows it, Enter copies its ID.
set -eu
self=$(realpath "$0")
# The views ctrl+s cycles through; "bead" is every bead that is not closed.
views=(bead open in_progress blocked deferred all)

list() { # $1: a view name, or "ready"
  # bd prints a format notice on stderr: it would land on top of fzf.
  case $1 in
    bead) bd list --json -n 0 --sort priority ;;
    all) bd list --json -n 0 --sort priority --all ;;
    ready) bd ready --json -n 0 ;;
    *) bd list --json -n 0 --sort priority --status "$1" ;;
  esac 2>/dev/null | jq -r '
    def pad(n): . + (" " * ([n - length, 1] | max));
    def paint(c): "\u001b[\(c)m\(.)\u001b[0m";
    def status_colour: {open: "32", in_progress: "33", blocked: "31", deferred: "90", closed: "90"}[.] // "37";
    def prio_colour: if . <= 1 then "31" elif . >= 3 then "90" else "37" end;
    .[] | . as $b
    | "\($b.id | pad(11))\("P\($b.priority)" | pad(4) | paint($b.priority | prio_colour))\($b.status | pad(12) | paint($b.status | status_colour))\($b.title)"'
}

# CLICOLOR_FORCE keeps bd's colours off a terminal; sed strips its (coloured) padding.
show() {
  CLICOLOR_FORCE=1 bd show "$1" 2>/dev/null |
    sed -E 's/((\x1b\[[0-9;]*m)*[[:space:]](\x1b\[[0-9;]*m)*)*$//'
}

# fzf hands the prompt to its commands: the prompt names the view on screen.
view() { echo "${FZF_PROMPT%> }"; }

case ${1:-} in
  list) list "$2"; exit ;;
  preview) show "$2"; exit ;;
  read) show "$2" | less -R; exit ;;
  next)
    next=${views[0]}
    for i in "${!views[@]}"; do
      [ "${views[i]}" = "$(view)" ] && next=${views[(i + 1) % ${#views[@]}]}
    done
    echo "reload($self list $next)+change-prompt($next> )"
    exit ;;
  ready) # alt+r toggles the ready view
    if [ "$(view)" = ready ]; then echo "reload($self list bead)+change-prompt(bead> )"
    else echo "reload($self list ready)+change-prompt(ready> )"; fi
    exit ;;
  claim)
    bd update "$2" --claim >/dev/null 2>&1 || true
    echo "reload($self list $(view))"
    exit ;;
esac

# A popup is not a pane: start from the directory of the pane it opened over.
cd "$("${HERDR_BIN_PATH:-herdr}" pane current | jq -r '.result.pane.foreground_cwd // .result.pane.cwd // env.HOME')"
if ! command -v bd >/dev/null 2>&1; then
  msg="bd is not installed"
elif ! bd where >/dev/null 2>&1; then
  msg="No beads in $PWD"
fi
if [ -n "${msg:-}" ]; then
  echo "$msg (press a key)"
  read -rsn1
  exit 0
fi
# Keys in the prompt's orange, what they do in grey; a blank line keeps the prompt clear.
key() { printf '\e[38;2;217;119;87m%s\e[0m %s  ' "$1" "$2"; }
help="$(key enter copy; key alt+enter read; key ctrl+s status; key alt+r ready; key alt+c claim)"$'\n '
line=$(list bead |
  # --height=100%: the popup is the whole window, whatever FZF_DEFAULT_OPTS says.
  fzf --ansi --no-hscroll --height=100% --layout=reverse --info=inline-right --border=none \
    --prompt='bead> ' --header-first \
    --header="$help" \
    --bind="ctrl-s:transform:$self next" \
    --bind="alt-r:transform:$self ready" \
    --bind="alt-c:transform:$self claim {1}" \
    --bind='ctrl-/:toggle-preview' \
    --bind="alt-enter:execute($self read {1})" \
    --preview="$self preview {1}" \
    --preview-window=right,55%,wrap-word,border-left,noinfo --preview-wrap-sign=' ' \
    --color='fg+:#ebdbb2,bg+:#3a3a3a,hl:#d97757,hl+:#d97757,prompt:#d97757,pointer:#d97757,border:#665c54,info:#8b8e9c,header:#8b8e9c') || exit 0
if command -v wl-copy >/dev/null 2>&1; then copy=wl-copy; else copy=pbcopy; fi
printf '%s' "${line%% *}" | "$copy"
