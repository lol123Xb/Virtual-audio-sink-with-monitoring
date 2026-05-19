#!/usr/bin/env bash

# Function to get the current active physical sink (speakers or Bluetooth)
get_physical_sink() {
  # Get the default sink, but exclude our virtual sinks
  local default=$(pactl get-default-sink)
  
  if [[ "$default" == "Desktop" || "$default" == "Discord" || "$default" == "Music" ]]; then
    # Find the first real hardware sink
    pactl list short sinks | grep -v -E "Desktop|Discord|Music" | head -1 | awk '{print $2}'
  else
    echo "$default"
  fi
}

# Create the master Desktop sink (captures ALL desktop audio)
create_master_desktop_sink() {
  if pactl list short sinks | grep -q "Desktop"; then
    echo "Desktop sink already exists"
  else
    echo "Creating Desktop sink (captures all desktop audio)"
    pactl load-module module-null-sink \
      sink_name=Desktop \
      sink_properties=device.description="Desktop Audio (All)"
  fi
}

# Create isolated sinks for Discord and Music
create_isolated_sink() {
  local sink_name=$1
  local description=$2
  
  if pactl list short sinks | grep -q "$sink_name"; then
    echo "$sink_name sink already exists"
  else
    echo "Creating $sink_name isolated sink"
    pactl load-module module-null-sink \
      sink_name="$sink_name" \
      sink_properties=device.description="$description"
  fi
}

# Update loopbacks to current physical sink
update_loopbacks() {
  local physical_sink=$(get_physical_sink)
  echo "Routing to physical sink: $physical_sink"
  
  # Remove old loopbacks
  pactl list short loopbacks | while read id src sink; do
    if [[ "$src" == "Desktop.monitor" || "$src" == "Discord.monitor" || "$src" == "Music.monitor" ]]; then
      pactl unload-module "$id" 2>/dev/null
    fi
  done
  
  # Create new loopbacks
  pactl load-module module-loopback source=Desktop.monitor sink="$physical_sink"
  pactl load-module module-loopback source=Discord.monitor sink="$physical_sink"
  pactl load-module module-loopback source=Music.monitor sink="$physical_sink"
}

# Main execution
echo "=== Setting up audio routing ==="
create_master_desktop_sink
create_isolated_sink "Discord" "Discord"
create_isolated_sink "Music" "Music"
update_loopbacks

echo ""
echo "✅ Setup complete!"
echo ""
