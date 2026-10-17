#!/usr/bin/env bash
# herdr labels a new workspace after its folder; keep the folder name, drop the capitals.
set -eu
read -r id label < <(jq -r '[.. | objects | select(has("workspace_id") and has("label"))][0] | "\(.workspace_id) \(.label)"' <<<"$HERDR_PLUGIN_EVENT_JSON")
[ "$label" = "${label,,}" ] || "${HERDR_BIN_PATH:-herdr}" workspace rename "$id" "${label,,}" >/dev/null
