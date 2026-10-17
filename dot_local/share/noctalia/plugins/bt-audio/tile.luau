--!nonstrict
-- Control-center tile: lit while the headset sits in HFP. Click: back to A2DP. Right click: reconnect.

local SCRIPT = "~/.config/scripts/bt-audio-fix"
local PROFILE = [[pw-dump | jq -r '.[] | select(.type=="PipeWire:Interface:Device" and .info.props["device.api"]=="bluez5") | .info.params.Profile[0].name' | head -1]]

local function render(profile)
    -- "off" is a connected headset with no audio profile: no use for the tile either
    local present = profile ~= "" and profile ~= "off"
    local hfp = present and not profile:find("^a2dp")
    shortcut.setEnabled(present)
    shortcut.setActive(hfp)
    shortcut.setLabel(if not present then "Headset" elseif hfp then "HFP" else "A2DP")
end

local function refresh()
    noctalia.runAsync(PROFILE, function(result)
        render(noctalia.string.trim(result.stdout or ""))
    end)
end

shortcut.setIcon("microphone", "headphones")
noctalia.setUpdateInterval(2000)
refresh()

function update()
    refresh()
end

function onClick()
    noctalia.runAsync(SCRIPT, refresh)
end

function onRightClick()
    noctalia.runAsync(`{SCRIPT} --reconnect`, refresh)
end
