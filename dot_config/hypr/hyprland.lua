-- ── Variables ────────────────────────────────────────────────────────
local terminal = "ghostty"
local mod      = "SUPER"

-- ── Machine detection ────────────────────────────────────────────────
local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local nvidia = file_exists("/sys/module/nvidia/version")

local sys = dofile(os.getenv("HOME") .. "/.config/hypr/system.lua")

-- ── Workspace layout ─────────────────────────────────────────────────
-- workspaces are global, so each screen owns a band: 1 to N on the main one,
-- 11 to 10 + N on the second external, one workspace on the side screen
local PER_SCREEN = sys.shell == "quickshell" and 4 or 8
local SIDE_WS    = PER_SCREEN + 1

-- how many of each band stay in the bar while empty; quickshell keeps its whole row
local ALWAYS = sys.shell == "quickshell" and PER_SCREEN or 4

-- ── Monitors ─────────────────────────────────────────────────────────
-- no 1.75: no real resolution is divisible by it on both axes
local SCALES = { 1, 1.25, 1.5, 2 }

-- nudge from the centre of the external row, in logical points; negative goes left
local LAPTOP_SHIFT = -320

-- the dpi rule would give 1.5, too little room. the lockscreen geometry in
-- noctalia/config.toml follows this value: change both
local LAPTOP_SCALE = 1.25

-- same apparent text size on every screen, with a whole logical resolution
local function best_scale(m)
    if m.physical_width == 0 then return 1 end
    local dpi, best = m.width / (m.physical_width / 25.4), 1
    for _, s in ipairs(SCALES) do
        if s <= dpi / 96 and m.width % s == 0 and m.height % s == 0 then best = s end
    end
    return best
end

local function is_laptop(m) return m.name:match("^eDP") or m.name:match("^LVDS") end

local ws_rules = {}

-- roles, refreshed on every hotplug
local plan = {}

-- MOD + n acts on the band of the focused screen; the side screen falls back to main
local function focused_ws(i)
    local m = hl.get_active_monitor()
    if m and m.name == plan.second then return 10 + i end
    return i
end

local function arrange()
    local externals, laptop = {}, nil
    for _, m in ipairs(hl.get_monitors()) do
        if is_laptop(m) then laptop = m else externals[#externals + 1] = m end
    end
    if #externals == 0 and not laptop then return end

    -- widest first. two identical screens tie on width, and the tie must be stable
    -- across hotplugs: the highest serial takes the left
    table.sort(externals, function(a, b)
        if a.width ~= b.width then return a.width > b.width end
        return a.serial > b.serial
    end)

    -- the row is as tall as its tallest screen, so the laptop clears all of them
    local x, row_height = 0, 0
    for _, m in ipairs(externals) do
        local s = best_scale(m)
        -- highres, not highrr: a 60 Hz 1080p panel that also lists 1024x768@75 loses
        -- its resolution to the refresh rate
        hl.monitor({ output = m.name, mode = "highres", position = string.format("%dx0", x), scale = s })
        x = x + math.floor(m.width / s)
        row_height = math.max(row_height, math.floor(m.height / s))
    end
    if laptop then
        local s = LAPTOP_SCALE
        -- centred under the whole external row: the cursor then crosses down from
        -- either screen, instead of from the left one only
        local left = math.max(0, math.floor((x - math.floor(laptop.width / s)) / 2) + LAPTOP_SHIFT)
        hl.monitor({ output = laptop.name, mode = "preferred",
                     position = string.format("%dx%d", left, row_height), scale = s })
    end

    plan.main   = externals[1] and externals[1].name or laptop.name
    plan.laptop = laptop and laptop.name
    -- the side workspace sits on the laptop panel, or on the second external when the
    -- machine has no laptop
    plan.side   = plan.laptop or (externals[2] and externals[2].name)
    -- the second external gets its own band, but only when it does not already hold
    -- the side workspace
    plan.second = externals[2] and externals[2].name ~= plan.side and externals[2].name
    hl.config({ cursor = { default_monitor = plan.main } })

    for _, r in ipairs(ws_rules) do r:set_enabled(false) end
    ws_rules = {}

    local function place(ws, monitor, default, persist)
        ws_rules[#ws_rules + 1] = hl.workspace_rule({
            workspace = tostring(ws), monitor = monitor, default = default, persistent = persist,
        })
    end

    for i = 1, PER_SCREEN do
        place(i, plan.main, i == 1, i <= ALWAYS)
        if plan.second then place(10 + i, plan.second, i == 1, i <= ALWAYS) end
    end
    -- the side one falls back to the main screen, where it is not the default: 1 is.
    -- always persistent, so that screen never ends up with an empty bar.
    place(SIDE_WS, plan.side or plan.main, plan.side ~= nil and plan.side ~= plan.main, true)
end

-- on a reload the monitors are already up; on a cold start they are not yet
arrange()
hl.on("monitor.added",   arrange)
hl.on("monitor.removed", arrange)

local local_lua = os.getenv("HOME") .. "/.config/hypr/local.lua"
if file_exists(local_lua) then dofile(local_lua) end

-- ── Environment variables ────────────────────────────────────────────
hl.env("XCURSOR_THEME",                       "breeze_cursors")
hl.env("XCURSOR_SIZE",                        "24")
hl.env("HYPRCURSOR_SIZE",                     "24")
hl.env("MOZ_ENABLE_WAYLAND",                  "1")
hl.env("QT_QPA_PLATFORM",                     "wayland;xcb")
if file_exists("/usr/bin/qt6ct") then
    hl.env("QT_QPA_PLATFORMTHEME",            "qt6ct")
end
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT",        "auto")
hl.env("STEAM_ENABLE_WAYLAND_CEF",  "1")

if nvidia then
    hl.env("LIBVA_DRIVER_NAME",          "nvidia")
    hl.env("__GLX_VENDOR_LIBRARY_NAME",  "nvidia")
    hl.env("NVD_BACKEND",                "direct")
    hl.env("AQ_DRM_DEVICES",             "/dev/dri/nvidia")

    -- G-Sync and VRR at driver level
    hl.env("__GL_GSYNC_ALLOWED", "1")
    hl.env("__GL_VRR_ALLOWED",   "1")
end

-- ── Shell layer ──────────────────────────────────────────────────────
local scripts = os.getenv("HOME") .. "/.config/scripts/"
-- raises the window if the app already runs, instead of a second instance
local focus   = scripts .. "launch-or-focus "

-- the backlight is on the laptop panel; without one, noctalia falls back to the
-- focused output
local function target()
    return plan.laptop and (" " .. plan.laptop) or ""
end

local shells = {
    -- noctalia owns polkit, idle, lock, nightlight, OSD, clipboard and wallpaper.
    noctalia = {
        autostart = { "sh -c 'LC_TIME=en_US.UTF-8 exec noctalia'" },
        launcher  = "noctalia msg panel-toggle launcher",
        calc      = "noctalia msg panel-toggle launcher /calc",
        emoji     = "noctalia msg panel-toggle launcher /emo",
        bluetooth = "noctalia msg panel-toggle control-center bluetooth",
        wallpaper = "noctalia msg panel-toggle wallpaper",
        lock      = "noctalia msg session lock",
        powermenu = "noctalia msg panel-toggle session",
        clipboard = "noctalia msg panel-toggle clipboard",
        notifications = "noctalia msg panel-toggle notification-history",
        dnd       = "noctalia msg notification-dnd-toggle",
        record    = "noctalia msg plugin 'noctalia/screen_recorder:service' all toggle",
        region    = "noctalia msg screenshot-region",
        -- noctalia has no per-window capture; the key picks an output instead
        window    = "noctalia msg screenshot-fullscreen pick",
        output    = "noctalia msg screenshot-fullscreen",
        ocr       = scripts .. "ocr",
        volume = {
            raise     = "noctalia msg volume-up",
            lower     = "noctalia msg volume-down",
            mute      = "noctalia msg volume-mute",
            mic_mute  = "noctalia msg mic-mute",
        },
        brightness = {
            -- closures: arrange() fills plan after this table is built, so the
            -- target is read at keypress time
            raise     = function() return "noctalia msg brightness-up" .. target() end,
            lower     = function() return "noctalia msg brightness-down" .. target() end,
        },
        layers = {
            { namespace = "^noctalia-(bar-.*|notification|dock|panel|attached-panel|osd)$", blur = true },
        },
        apps = {
            discord  = "flatpak run com.discordapp.Discord",
            obsidian = "flatpak run md.obsidian.Obsidian",
            slack    = "flatpak run com.slack.Slack",
            zed      = "zed",
        },
    },
    -- quickshell owns everything the desktop draws: bar, notifications, launcher
    -- with calc and emoji, OSD, polkit, idle, lock, wallpaper, session and the
    -- audio and bluetooth panels.
    quickshell = {
        autostart = {
            -- a different wallpaper each session; the theme follows it
            "sh -c 'ls ~/Pictures/Wallpapers/* | shuf -n 1 > ~/.cache/hypr/current-wallpaper'",
            "qs",
            "hyprsunset -t 3500",
            -- its unit has Requisite=graphical-session.target, which hyprland
            -- never activates; without it libadwaita gets no accent colour
            "/usr/lib/xdg-desktop-portal-gnome",
            "sh -c 'export PATH=/usr/bin:$PATH; clipse -listen'",
        },
        launcher  = "qs ipc call launcher toggle",
        calc      = "qs ipc call launcher calc",
        emoji     = "qs ipc call launcher emoji",
        bluetooth = "qs ipc call controlcenter bluetooth",
        wallpaper = "qs ipc call wallpaper toggle",
        lock      = "qs ipc call lock lock",
        powermenu = "qs ipc call session toggle",
        clipboard = "qs ipc call clipboard toggle",
        notifications = "qs ipc call notifications toggle",
        dnd       = "qs ipc call notifications dnd",
        nightlight = "qs ipc call nightlight toggle",
        record    = scripts .. "record",
        region    = "qs ipc call screenshot region",
        window    = "qs ipc call screenshot window",
        output    = "qs ipc call screenshot output",
        ocr       = "qs ipc call screenshot ocr",
        volume = {
            raise     = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+",
            lower     = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-",
            mute      = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
            mic_mute  = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle",
        },
        brightness = {
            raise     = function() return "brightnessctl set 5%+" end,
            lower     = function() return "brightnessctl set 5%-" end,
        },
        layers = {
            { namespace = "^quickshell$",                                blur = false },
            { namespace = "^quickshell-(launcher|clipboard|polkit|session|control-center|wallpaper-picker|notification.*)$",
              blur = true, ignore_alpha = 0.5 },
        },
        apps = {
            discord  = "discord",
            obsidian = "obsidian",
            zed      = "zeditor",
        },
    },
}
local sh = assert(shells[sys.shell], "unknown shell layer in system.lua: " .. tostring(sys.shell))

-- ── Autostart ────────────────────────────────────────────────────────
hl.on("hyprland.start", function()
    -- the whole session environment, so portals and everything dbus starts
    -- see the same variables as hyprland itself
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    arrange()
    for _, cmd in ipairs(sh.autostart) do
        hl.exec_cmd(cmd)
    end
end)

-- ── Config ───────────────────────────────────────────────────────────
hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 1,
        col = {
            active_border   = { colors = { "rgba(928374aa)", "rgba(a89984aa)" }, angle = 45 },
            inactive_border = "rgba(45475aaa)",
        },
        layout           = "dwindle",
        resize_on_border = true,
    },

    input = {
        kb_layout          = "fr",
        numlock_by_default = true,
        follow_mouse       = 1,
        sensitivity        = -0.1,
        accel_profile      = "flat",
    },

    decoration = {
        rounding = 10,
        blur = {
            enabled = true,
            size    = 3,
            passes  = 1,
        },
        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = "rgba(1a1a1aee)",
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        vrr                      = 2,
        -- a link opened from another app raises the browser, workspace included
        focus_on_activate        = true,
    },

    cursor = {
        no_hardware_cursors  = true,
    },

    xwayland = {
        force_zero_scaling = true,
    },
})

-- ── Animations ───────────────────────────────────────────────────────
hl.curve("ease", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

hl.animation({ leaf = "windows",    enabled = true, speed = 7, bezier = "ease" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 7, bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 7, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "default" })

-- ── Application shortcuts ────────────────────────────────────────────
hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + CTRL + Return", hl.dsp.exec_cmd(focus .. "herdr " .. terminal .. " --class=herdr.ghostty -e herdr"))
hl.bind(mod .. " + Space", hl.dsp.exec_cmd(sh.launcher))
hl.bind(mod .. " + B", hl.dsp.exec_cmd([[sh -c 'gtk-launch "$(xdg-settings get default-web-browser)"']]))
hl.bind(mod .. " + D", hl.dsp.exec_cmd(focus .. "discord " .. sh.apps.discord))
hl.bind(mod .. " + SHIFT + B", hl.dsp.exec_cmd(sh.bluetooth))
hl.bind(mod .. " + E", hl.dsp.exec_cmd(focus .. "org.gnome.Nautilus nautilus"))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd(terminal .. " -e yazi"))
hl.bind(mod .. " + Z", hl.dsp.exec_cmd(focus .. "dev.zed.Zed " .. sh.apps.zed))
hl.bind(mod .. " + O", hl.dsp.exec_cmd(focus .. "obsidian " .. sh.apps.obsidian))
if sh.apps.slack then
    hl.bind(mod .. " + S", hl.dsp.exec_cmd(focus .. "Slack " .. sh.apps.slack))
end
hl.bind(mod .. " + SHIFT + W", hl.dsp.exec_cmd(sh.wallpaper))
hl.bind(mod .. " + SHIFT + T", hl.dsp.exec_cmd(sh.ocr))
hl.bind(mod .. " + COLON", hl.dsp.exec_cmd(sh.emoji))
hl.bind(mod .. " + EQUAL", hl.dsp.exec_cmd(sh.calc))
hl.bind(mod .. " + P", hl.dsp.exec_cmd("hyprpicker -a"))

-- ── Window management ────────────────────────────────────────────────
hl.bind(mod .. " + Q", hl.dsp.window.close())
-- close, not kill: every app gets to save before the session empties
hl.bind("CTRL + ALT + Delete", function()
    for _, w in ipairs(hl.get_windows()) do
        hl.dispatch(hl.dsp.window.close({ window = "address:" .. w.address }))
    end
end)
hl.bind(mod .. " + CTRL + SHIFT + M", hl.dsp.exit())
hl.bind(mod .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind(mod .. " + X", hl.dsp.layout("togglesplit"))
hl.bind(mod .. " + L", hl.dsp.exec_cmd(sh.lock))
hl.bind(mod .. " + SHIFT + Q", hl.dsp.exec_cmd(sh.powermenu))

-- ── Focus ────────────────────────────────────────────────────────────
hl.bind(mod .. " + left", hl.dsp.focus({ direction = "l" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mod .. " + up", hl.dsp.focus({ direction = "u" }))
hl.bind(mod .. " + down", hl.dsp.focus({ direction = "d" }))

-- ── Move windows ─────────────────────────────────────────────────────
hl.bind(mod .. " + SHIFT + left", hl.dsp.window.move({ direction = "l" }))
hl.bind(mod .. " + SHIFT + right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mod .. " + SHIFT + up", hl.dsp.window.move({ direction = "u" }))
hl.bind(mod .. " + SHIFT + down", hl.dsp.window.move({ direction = "d" }))

-- ── Workspaces ───────────────────────────────────────────────────────
-- the number keys, by keycode: this azerty layout puts a symbol on their first level
for i = 1, PER_SCREEN do
    -- closures, so the band is picked at keypress from the focused screen
    hl.bind(mod .. " + code:" .. (9 + i), function()
        hl.dispatch(hl.dsp.focus({ workspace = focused_ws(i) }))
    end)
    hl.bind(mod .. " + SHIFT + code:" .. (9 + i), function()
        hl.dispatch(hl.dsp.window.move({ workspace = focused_ws(i) }))
    end)
end
-- MOD + twosuperior doubles the side key
hl.bind(mod .. " + code:" .. (9 + SIDE_WS), hl.dsp.focus({ workspace = SIDE_WS }))
hl.bind(mod .. " + SHIFT + code:" .. (9 + SIDE_WS), hl.dsp.window.move({ workspace = SIDE_WS }))
hl.bind(mod .. " + twosuperior", hl.dsp.focus({ workspace = SIDE_WS }))
hl.bind(mod .. " + SHIFT + twosuperior", hl.dsp.window.move({ workspace = SIDE_WS }))
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mod .. " + TAB", hl.dsp.focus({ window = "next" }))
hl.bind(mod .. " + SHIFT + TAB", hl.dsp.focus({ window = "prev" }))

-- ── Mouse ────────────────────────────────────────────────────────────
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ── Screenshots ──────────────────────────────────────────────────────
hl.bind("Print", hl.dsp.exec_cmd(sh.output))
hl.bind(mod .. " + SHIFT + S", hl.dsp.exec_cmd(sh.region))
hl.bind(mod .. " + SHIFT + Print", hl.dsp.exec_cmd(sh.window))

-- ── Volume ───────────────────────────────────────────────────────────
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(sh.volume.raise), { repeating = true, locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(sh.volume.lower), { repeating = true, locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(sh.volume.mute), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(sh.volume.mic_mute), { locked = true })
hl.bind("mouse:275", hl.dsp.exec_cmd(sh.volume.mic_mute), { mouse = true, locked = true })

-- ── Brightness ───────────────────────────────────────────────────────
hl.bind("XF86MonBrightnessUp", function() hl.dispatch(hl.dsp.exec_cmd(sh.brightness.raise())) end,
        { repeating = true, locked = true })
hl.bind("XF86MonBrightnessDown", function() hl.dispatch(hl.dsp.exec_cmd(sh.brightness.lower())) end,
        { repeating = true, locked = true })

-- ── Resize submap ────────────────────────────────────────────────────
hl.bind(mod .. " + R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    hl.bind("right", hl.dsp.window.resize({ x =  10, y =   0, relative = true }), { repeating = true })
    hl.bind("left", hl.dsp.window.resize({ x = -10, y =   0, relative = true }), { repeating = true })
    hl.bind("down", hl.dsp.window.resize({ x =   0, y =  10, relative = true }), { repeating = true })
    hl.bind("up", hl.dsp.window.resize({ x =   0, y = -10, relative = true }), { repeating = true })
    hl.bind("escape", hl.dsp.submap("reset"))
    hl.bind("Return", hl.dsp.submap("reset"))
end)

-- ── Misc ─────────────────────────────────────────────────────────────
hl.bind(mod .. " + SHIFT + C", hl.dsp.exec_cmd(sh.clipboard))
hl.bind(mod .. " + N", hl.dsp.exec_cmd(sh.notifications))
hl.bind(mod .. " + SHIFT + P", hl.dsp.exec_cmd(sh.dnd))
if sh.nightlight then
    hl.bind(mod .. " + SHIFT + N", hl.dsp.exec_cmd(sh.nightlight))
end
hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd(sh.record))

-- ── Layer rules ──────────────────────────────────────────────────────
for _, l in ipairs(sh.layers) do
    hl.layer_rule({ match = { namespace = l.namespace }, blur = l.blur, ignore_alpha = l.ignore_alpha })
end

-- ── Window rules ─────────────────────────────────────────────────────
hl.window_rule({ match = { class = "com.saivert.pwvucontrol" }, float = true })
-- dialogs: a floating window opens centred, never under the bar; the portal
-- file chooser is tiled by default and reads better as a floating sheet
hl.window_rule({ match = { float = true, title = "negative:^vlc$" }, center = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, float = true, center = true, size = "1200 800" })
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

-- ── Noctalia colors ──────────────────────────────────────────────────
if sys.shell == "noctalia" and file_exists(os.getenv("HOME") .. "/.config/hypr/noctalia.lua") then
    require("noctalia").apply_theme()
end
