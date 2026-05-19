#!/usr/bin/env bash

# Configuration
MONITOR_PID_FILE="/tmp/audio-monitor.pid"

# Function to get ALL sink input IDs that match a pattern in name or binary
get_sink_input_ids_by_pattern() {
  local pattern=$1
  
  # Get all sink inputs and check each one
  pactl list sink-inputs short | awk '{print $1}' | while read id; do
    # Get the full sink input info
    local info=$(pactl list sink-inputs | grep -A 30 "Sink Input #$id")
    
    # Get application name
    local app_name=$(echo "$info" | grep "application.name" | head -1 | sed 's/.*= "\(.*\)"/\1/')
    
    # Get application process binary
    local app_binary=$(echo "$info" | grep "application.process.binary" | head -1 | sed 's/.*= "\(.*\)"/\1/')
    
    # Check if pattern matches either name or binary
    if [[ "$app_name" =~ $pattern ]] || [[ "$app_name" == *"$pattern"* ]] || \
       [[ "$app_binary" =~ $pattern ]] || [[ "$app_binary" == *"$pattern"* ]]; then
      echo "$id"
    fi
  done
}

# Function to move a specific sink input by ID
move_sink_input_to_sink() {
  local sink_id=$1
  local sink_name=$2
  
  pactl move-sink-input "$sink_id" "$sink_name" 2>/dev/null
}

# Function to move ALL Wine/Proton games to Desktop
move_all_games_to_desktop() {
  # Patterns that identify Wine/Proton games
  local game_patterns=(
    "wine"
    "preloader"
    "Wine"
    "\.exe"
    "steam"
    "game"
    "Game"
  )
  
  for pattern in "${game_patterns[@]}"; do
    get_sink_input_ids_by_pattern "$pattern" | while read id; do
      if [ -n "$id" ]; then
        move_sink_input_to_sink "$id" "Desktop"
      fi
    done
  done
}

# Move specific applications by exact name or binary
move_application_to_sink() {
  local app_name=$1
  local sink_name=$2
  
  get_sink_input_ids_by_pattern "$app_name" | while read id; do
    if [ -n "$id" ]; then
      move_sink_input_to_sink "$id" "$sink_name"
    fi
  done
}

# Monitor for new applications
monitor_apps() {
  echo "=== Audio Monitor Started ==="
  echo "Monitoring for new audio applications..."
  echo "Rules:"
  echo "  • All Wine/Proton games → Desktop"
  echo "  • Chromium → Music"
  echo "  • OBS → Desktop"
  echo "  • WEBRTC VoiceEngine/Discord → Discord"
  echo "  • (all others) → Desktop"
  echo ""
  echo "Monitor PID: $$"
  echo "To stop: kill $$ or run '$0 --stop'"
  echo "================================"
  
  # Process existing apps first
  move_all_games_to_desktop
  move_application_to_sink "Chromium" "Music"
  move_application_to_sink "OBS" "Desktop"
  move_application_to_sink "WEBRTC VoiceEngine" "Discord"
  move_application_to_sink "Discord" "Discord"
  
  # Monitor for new sink inputs
  pactl subscribe 2>/dev/null | while read event; do
    if echo "$event" | grep -q "sink-input"; then
      # New audio application appeared
      sleep 5  # Wait for app to fully initialize
      
      # Find the most recent sink input
      local new_sink_id=$(pactl list sink-inputs short | tail -1 | awk '{print $1}')
      
      if [ -n "$new_sink_id" ]; then
        local info=$(pactl list sink-inputs | grep -A 30 "Sink Input #$new_sink_id")
        local app_name=$(echo "$info" | grep "application.name" | head -1 | sed 's/.*= "\(.*\)"/\1/')
        local app_binary=$(echo "$info" | grep "application.process.binary" | head -1 | sed 's/.*= "\(.*\)"/\1/')
        local current_sink=$(echo "$info" | grep "Sink:" | head -1 | awk '{print $2}')
        
        # Determine target sink
        local target_sink="Desktop"
        
        if [[ "$app_name" == *"Chromium"* ]]; then
          target_sink="Music"
        elif [[ "$app_name" == *"WEBRTC"* ]] || [[ "$app_name" == *"Discord"* ]]; then
          target_sink="Discord"
        elif [[ "$app_binary" == *"wine"* ]] || [[ "$app_binary" == *"preloader"* ]]; then
          target_sink="Desktop"
        fi
        
        # Move if needed
        if [ "$current_sink" != "$target_sink" ]; then
          echo "[$(date '+%H:%M:%S')] New app: $app_name → moving to $target_sink"
          pactl move-sink-input "$new_sink_id" "$target_sink"
        fi
      fi
    fi
  done
}

# Stop the monitor
stop_monitor() {
  if [ -f "$MONITOR_PID_FILE" ]; then
    local pid=$(cat "$MONITOR_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Stopping audio monitor (PID: $pid)"
      kill "$pid"
      rm -f "$MONITOR_PID_FILE"
      echo "Monitor stopped"
    else
      echo "Monitor not running (stale PID file)"
      rm -f "$MONITOR_PID_FILE"
    fi
  else
    local pid=$(pgrep -f "remap.sh --monitor")
    if [ -n "$pid" ]; then
      echo "Stopping audio monitor (PID: $pid)"
      kill $pid
      echo "Monitor stopped"
    else
      echo "No running monitor found"
    fi
  fi
}

# Main execution
case "$1" in
  --monitor)
    echo $$ > "$MONITOR_PID_FILE"
    monitor_apps
    ;;
  --stop)
    stop_monitor
    ;;
  --help)
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "  (no args)     Move all games and apps to correct sinks (default)"
    echo "  --monitor     Start auto-routing monitor (runs in background)"
    echo "  --stop        Stop the background monitor"
    echo "  --help        Show this help"
    echo ""
    ;;
  *)
    # Default behavior: move everything
    echo "=== Moving Games to Desktop ==="
    move_all_games_to_desktop
    
    echo ""
    echo "=== Moving Other Apps ==="
    move_application_to_sink "Chromium" "Music"
    move_application_to_sink "OBS" "Desktop"
    move_application_to_sink "WEBRTC VoiceEngine" "Discord"
    move_application_to_sink "Discord" "Discord"
    
    echo ""
    echo "=== Done ==="
    ;;
esac
