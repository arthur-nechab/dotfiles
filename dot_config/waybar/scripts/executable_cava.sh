#!/usr/bin/env bash

config_file="/tmp/waybar_cava_config"
trap 'rm -f "$config_file"' EXIT
cat > "$config_file" <<'EOF'
[general]
bars = 10

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
EOF

cava -p "$config_file" | sed -u 's/;//g; y/01234567/▁▂▃▄▅▆▇█/'
