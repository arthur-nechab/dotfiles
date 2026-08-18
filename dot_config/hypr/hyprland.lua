-- ── Variables ────────────────────────────────────────────────────────
local terminal = "ghostty"
local menu     = "rofi"
local mod      = "SUPER"

-- ── Monitors ─────────────────────────────────────────────────────────
hl.monitor({ output = "DP-2",      mode = "3840x2160@144", position = "0x0",    scale = 1.5 })
hl.monitor({ output = "HDMI-A-3",  mode = "1920x1080@60",  position = "2560x0", scale = 1   })
hl.monitor({ output = "Unknown-1", disabled = true })  -- NVIDIA ghost output

-- ── Workspaces ───────────────────────────────────────────────────────
hl.workspace_rule({ workspace = "1", monitor = "DP-2",     default = true, persistent = true })
hl.workspace_rule({ workspace = "2", monitor = "DP-2",                     persistent = true })
hl.workspace_rule({ workspace = "3", monitor = "DP-2",                     persistent = true })
hl.workspace_rule({ workspace = "4", monitor = "DP-2",                     persistent = true })
hl.workspace_rule({ workspace = "5", monitor = "HDMI-A-3", default = true, persistent = true })

-- ── Environment variables ────────────────────────────────────────────
hl.env("XCURSOR_SIZE",                        "24")
hl.env("HYPRCURSOR_SIZE",                     "24")
hl.env("MOZ_ENABLE_WAYLAND",                  "1")
hl.env("QT_QPA_PLATFORM",                     "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT",        "auto")

-- NVIDIA
hl.env("LIBVA_DRIVER_NAME",          "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME",  "nvidia")
hl.env("NVD_BACKEND",                "direct")
hl.env("AQ_DRM_DEVICES",             "/dev/dri/nvidia")

-- Steam store and UI run on native Wayland, not on Xwayland
hl.env("STEAM_ENABLE_WAYLAND_CEF",  "1")

-- G-Sync and VRR at driver level
hl.env("__GL_GSYNC_ALLOWED", "1")
hl.env("__GL_VRR_ALLOWED",   "1")

-- ── Autostart ────────────────────────────────────────────────────────
hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("waybar")
    hl.exec_cmd("swaync")
    hl.exec_cmd(os.getenv("HOME") .. "/.config/scripts/launch-hyprpaper")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("hyprsunset -t 3500")

    hl.exec_cmd("swayosd-server")
    hl.exec_cmd("sh -c 'export PATH=/usr/bin:$PATH; clipse -listen'")
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
    },

    cursor = {
        no_hardware_cursors  = true,
        default_monitor      = "DP-2",
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
hl.bind(mod .. " + Return",    hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + Space",     hl.dsp.exec_cmd(menu .. " -show drun"))
hl.bind(mod .. " + B",         hl.dsp.exec_cmd("vivaldi"))
hl.bind(mod .. " + D",         hl.dsp.exec_cmd("discord"))
hl.bind(mod .. " + SHIFT + B", hl.dsp.exec_cmd("rofi-bluetooth"))
hl.bind(mod .. " + E",         hl.dsp.exec_cmd(terminal .. " -e yazi"))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd("thunar"))
hl.bind(mod .. " + Z",         hl.dsp.exec_cmd("zeditor"))
hl.bind(mod .. " + O",         hl.dsp.exec_cmd("obsidian"))
hl.bind(mod .. " + SHIFT + W",     hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/scripts/wallpaper-picker"))
hl.bind(mod .. " + SHIFT + T",  hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/scripts/ocr"))
hl.bind(mod .. " + PERIOD",    hl.dsp.exec_cmd("rofimoji --action type"))
hl.bind(mod .. " + EQUAL",     hl.dsp.exec_cmd(menu .. " -show calc -modi calc -no-show-match -no-sort"))
hl.bind(mod .. " + P",         hl.dsp.exec_cmd("hyprpicker -a"))

-- ── Window management ────────────────────────────────────────────────
hl.bind(mod .. " + Q",           hl.dsp.window.close())
hl.bind(mod .. " + CTRL + SHIFT + M", hl.dsp.exit())
hl.bind(mod .. " + SHIFT + F",   hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + F",           hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind(mod .. " + BACKSLASH",   hl.dsp.layout("togglesplit"))
hl.bind(mod .. " + L",           hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mod .. " + SHIFT + Q",   hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/scripts/powermenu"))

-- ── Focus ────────────────────────────────────────────────────────────
hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "l" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "u" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "d" }))

-- ── Move windows ─────────────────────────────────────────────────────
hl.bind(mod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "l" }))
hl.bind(mod .. " + SHIFT + right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "u" }))
hl.bind(mod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "d" }))

-- ── Workspaces (AZERTY: code:10=&, code:11=é, code:12=", code:13=') ──
hl.bind(mod .. " + code:10",             hl.dsp.focus({ workspace = 1 }))
hl.bind(mod .. " + code:11",             hl.dsp.focus({ workspace = 2 }))
hl.bind(mod .. " + code:12",             hl.dsp.focus({ workspace = 3 }))
hl.bind(mod .. " + code:13",             hl.dsp.focus({ workspace = 4 }))
hl.bind(mod .. " + twosuperior",         hl.dsp.focus({ workspace = 5 }))
hl.bind(mod .. " + SHIFT + code:10",     hl.dsp.window.move({ workspace = 1 }))
hl.bind(mod .. " + SHIFT + code:11",     hl.dsp.window.move({ workspace = 2 }))
hl.bind(mod .. " + SHIFT + code:12",     hl.dsp.window.move({ workspace = 3 }))
hl.bind(mod .. " + SHIFT + code:13",     hl.dsp.window.move({ workspace = 4 }))
hl.bind(mod .. " + SHIFT + twosuperior", hl.dsp.window.move({ workspace = 5 }))
hl.bind(mod .. " + TAB",                 hl.dsp.focus({ window = "next" }))
hl.bind(mod .. " + SHIFT + TAB",        hl.dsp.focus({ window = "prev" }))

-- ── Mouse ────────────────────────────────────────────────────────────
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ── Screenshots ──────────────────────────────────────────────────────
hl.bind("Print",                   hl.dsp.exec_cmd("hyprshot -m output -o ~/Pictures/Screenshots"))
hl.bind(mod .. " + SHIFT + S",     hl.dsp.exec_cmd("hyprshot -m region --clipboard-only"))
hl.bind(mod .. " + SHIFT + Print", hl.dsp.exec_cmd("hyprshot -m window --clipboard-only"))

-- ── Volume ───────────────────────────────────────────────────────────
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("swayosd-client --output-volume raise"),       { repeating = true, locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("swayosd-client --output-volume lower"),       { repeating = true, locked = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle"), { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && swayosd-client --input-volume mute-toggle"),  { locked = true })
hl.bind("mouse:275",            hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && swayosd-client --input-volume mute-toggle && pkill -RTMIN+8 waybar"), { mouse = true, locked = true })

-- ── Resize submap ────────────────────────────────────────────────────
hl.bind(mod .. " + R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    hl.bind("right",  hl.dsp.window.resize({ x =  10, y =   0, relative = true }), { repeating = true })
    hl.bind("left",   hl.dsp.window.resize({ x = -10, y =   0, relative = true }), { repeating = true })
    hl.bind("down",   hl.dsp.window.resize({ x =   0, y =  10, relative = true }), { repeating = true })
    hl.bind("up",     hl.dsp.window.resize({ x =   0, y = -10, relative = true }), { repeating = true })
    hl.bind("escape", hl.dsp.submap("reset"))
    hl.bind("Return", hl.dsp.submap("reset"))
end)

-- ── Misc ─────────────────────────────────────────────────────────────
hl.bind(mod .. " + SHIFT + V", hl.dsp.exec_cmd("ghostty --class=clipse -e clipse"))
hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/scripts/record"))

-- ── Layer rules ──────────────────────────────────────────────────────
hl.layer_rule({ match = { namespace = "waybar" },                blur = false })
hl.layer_rule({ match = { namespace = "swaync-control-center" }, blur = false })
hl.layer_rule({ match = { namespace = "rofi" },   blur = true, ignore_alpha = 0.5 })

-- ── Window rules ─────────────────────────────────────────────────────
hl.window_rule({ match = { class = "com.saivert.pwvucontrol" }, float = true })
hl.window_rule({ match = { class = "clipse" },                     float = true, size = "622 652", center = true })
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })  -- ignore maximize requests from applications
