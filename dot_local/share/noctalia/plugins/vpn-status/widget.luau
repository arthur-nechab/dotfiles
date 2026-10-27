--!nonstrict
-- Bar widget: one row per active NetworkManager tunnel (wireguard, tun).
-- Shows no profile name, address or domain, so the screen does not tell which VPN runs.

-- One line per tunnel: route|target|rtt|route count|rx tx
-- A tunnel is up when its DNS server (else its gateway, IPv4 first) answers through it; split when
-- the default route skips it. No target: no verdict, the plain shield.
local PROBE = [[
uplink=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p')
nmcli -t -f UUID,TYPE,DEVICE con show --active | while IFS=: read -r id type dev; do
  # shortcut: a vpn profile is seen through the tun device NetworkManager adopts; a VPN without
  # a tun device (IPsec) does not show, add the vpn type back if one is used
  case "$type" in wireguard|tun) ;; *) continue ;; esac
  target=$(nmcli -g IP4.DNS,IP4.GATEWAY,IP6.DNS,IP6.GATEWAY con show uuid "$id" | tr -s '| ' '\n' | grep -m1 .)
  # -I: a public target must not answer through the uplink
  rtt=$([ -n "$target" ] && ping -c1 -W1 -I "$dev" "$target" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p')
  [ "$uplink" = "$dev" ] && route=full || route=split
  routes=$( { ip -4 route show table all dev "$dev" type unicast; ip -6 route show table all dev "$dev" type unicast | grep -v '^fe80'; } | wc -l)
  bytes=$(ip -j -s link show "$dev" | jq -r '.[0].stats64 | "\(.rx.bytes) \(.tx.bytes)"' | numfmt --to=iec --field=1-2 | tr -s ' ')
  echo "$route|$target|$rtt|$routes|$bytes"
done
]]

local probe = ""

local function render()
    local rows, ok, probed = {}, true, true
    local i = 0
    for _, line in string.split(probe, "\n") do
        if line ~= "" then
            i += 1
            local route, target, rtt, routes, bytes = unpack(string.split(line, "|"))
            local rx, tx = string.match(bytes or "", "^(%S+) (%S+)$")
            local up = rtt ~= nil and rtt ~= ""
            ok = ok and (up or target == "")
            probed = probed and target ~= ""
            table.insert(rows, { `Tunnel {i}`, if up then `up, {rtt} ms` elseif target == "" then "not probed" else "does not answer" })
            table.insert(rows, { "Route", `{route}, {routes} routes` })
            table.insert(rows, { "Traffic", `{rx or "?"} in, {tx or "?"} out` })
        end
    end
    barWidget.setTooltip(rows)

    barWidget.setVisible(#rows > 0)
    barWidget.setText("")
    barWidget.setGlyph(if not ok then "shield-x" elseif probed then "shield-check" else "shield")
    barWidget.setGlyphColor(if ok then "on_surface" else "error")
end

local function refresh()
    noctalia.runAsync(PROBE, function(result)
        probe = noctalia.string.trim(result.stdout or "")
        render()
    end)
end

noctalia.setUpdateInterval(5000)
refresh()

function update()
    refresh()
end

function onClick()
    noctalia.runAsync("noctalia msg panel-toggle control-center network")
end
