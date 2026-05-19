#!/usr/bin/env bash

# Function to unload all modules by name pattern
unload_modules() {
  local pattern=$1
  echo "Finding modules matching pattern: $pattern"
  pactl list modules short | grep "$pattern" | while read -r module; do
    module_id=$(echo "$module" | awk '{print $1}')
    module_name=$(echo "$module" | awk '{print $2}')
    echo "Unloading module $module_id ($module_name)"
    pactl unload-module "$module_id"
  done
}

# Remove all sinks and loopbacks created for Audio1, Audio2, Audio3
unload_modules "module-null-sink"
unload_modules "module-loopback"

# Verify removal
echo "Remaining modules:"
pactl list modules short

echo "Audio sources and loopbacks removed successfully."
