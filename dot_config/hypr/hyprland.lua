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

-- ── Monitors ─────────────────────────────────────────────────────────
local main = "desc:GIGA-BYTE TECHNOLOGY CO. LTD. M28U"
hl.monitor({ output = main, mode = "3840x2160@144", position = "0x0",  scale = 1.5 })
hl.monitor({ output = "",   mode = "preferred",     position = "auto", scale = 1   })

for i = 1, 4 do
    hl.workspace_rule({ workspace = tostring(i), monitor = main, default = i == 1, persistent = true })
end
hl.workspace_rule({ workspace = "5", monitor = "desc:Dell Inc. DELL P2212H", default = true, persistent = true })

local local_lua = os.getenv("HOME") .. "/.config/hypr/local.lua"
if file_exists(local_lua) then dofile(local_lua) end

-- ── Environment variables ────────────────────────────────────────────
hl.env("XCURSOR_THEME",                       "breeze_cursors")
hl.env("XCURSOR_SIZE",                        "24")
hl.env("HYPRCURSOR_SIZE",                     "24")
hl.env("MOZ_ENABLE_WAYLAND",                  "1")
hl.env("QT_QPA_PLATFORM",                     "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME",                "qt6ct")
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
local sys     = dofile(os.getenv("HOME") .. "/.config/hypr/system.lua")
local scripts = os.getenv("HOME") .. "/.config/scripts/"
-- raises the window if the app already runs, instead of a second instance
local focus   = scripts .. "launch-or-focus "

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
        layers = {
            { namespace = "^noctalia-(bar-.*|notification|dock|panel|attached-panel|osd)$", blur = true },
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
        layers = {
            { namespace = "^quickshell$",                                blur = false },
            { namespace = "^quickshell-(launcher|clipboard|polkit|session|control-center|wallpaper-picker|notification.*)$",
              blur = true, ignore_alpha = 0.5 },
        },
    },
}
local sh = assert(shells[sys.shell], "unknown shell layer in system.lua: " .. tostring(sys.shell))

-- ── Autostart ────────────────────────────────────────────────────────
hl.on("hyprland.start", function()
    -- the whole session environment, so portals and everything dbus starts
    -- see the same variables as hyprland itself
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
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
        default_monitor      = main,
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
hl.bind(mod .. " + Space", hl.dsp.exec_cmd(sh.launcher))
hl.bind(mod .. " + B", hl.dsp.exec_cmd([[sh -c 'gtk-launch "$(xdg-settings get default-web-browser)"']]))
hl.bind(mod .. " + D", hl.dsp.exec_cmd(focus .. "discord discord"))
hl.bind(mod .. " + SHIFT + B", hl.dsp.exec_cmd(sh.bluetooth))
hl.bind(mod .. " + E", hl.dsp.exec_cmd(focus .. "org.gnome.Nautilus nautilus"))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd(terminal .. " -e yazi"))
hl.bind(mod .. " + Z", hl.dsp.exec_cmd(focus .. "dev.zed.Zed zeditor"))
hl.bind(mod .. " + O", hl.dsp.exec_cmd(focus .. "obsidian obsidian"))
hl.bind(mod .. " + SHIFT + W", hl.dsp.exec_cmd(sh.wallpaper))
hl.bind(mod .. " + SHIFT + T", hl.dsp.exec_cmd(sh.ocr))
hl.bind(mod .. " + COLON", hl.dsp.exec_cmd(sh.emoji))
hl.bind(mod .. " + EQUAL", hl.dsp.exec_cmd(sh.calc))
hl.bind(mod .. " + P", hl.dsp.exec_cmd("hyprpicker -a"))

-- ── Window management ────────────────────────────────────────────────
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + CTRL + SHIFT + M", hl.dsp.exit())
hl.bind(mod .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind(mod .. " + BACKSLASH", hl.dsp.layout("togglesplit"))
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
for i = 1, 5 do
    hl.bind(mod .. " + code:" .. (9 + i), hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + code:" .. (9 + i), hl.dsp.window.move({ workspace = i }))
end
hl.bind(mod .. " + twosuperior", hl.dsp.focus({ workspace = 5 }))
hl.bind(mod .. " + SHIFT + twosuperior", hl.dsp.window.move({ workspace = 5 }))
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
hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd(sh.record))

-- ── Layer rules ──────────────────────────────────────────────────────
for _, l in ipairs(sh.layers) do
    hl.layer_rule({ match = { namespace = l.namespace }, blur = l.blur, ignore_alpha = l.ignore_alpha })
end

-- ── Window rules ─────────────────────────────────────────────────────
hl.window_rule({ match = { class = "com.saivert.pwvucontrol" }, float = true })
-- dialogs: a floating window opens centred, never under the bar; the portal
-- file chooser is tiled by default and reads better as a floating sheet
hl.window_rule({ match = { float = true }, center = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, float = true, center = true, size = "1200 800" })
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })
