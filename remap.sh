#!/usr/bin/env bash

# Configuration
MONITOR_PID_FILE="/tmp/audio-monitor.pid"
MONITOR_LOG_FILE="/tmp/audio-monitor.log"

# Function to check if a sink input is from a loopback module by checking node.name
is_loopback_sink_input() {
  local sink_id=$1
  
  # Get the full sink input info
  local info=$(pactl list sink-inputs | grep -A 30 "Sink Input #$sink_id")
  
  # Check for node.name containing "loopback"
  local node_name=$(echo "$info" | grep "node.name" | head -1 | sed 's/.*= "\(.*\)"/\1/')
  
  if [[ "$node_name" == *"loopback"* ]] || [[ "$node_name" == *"Loopback"* ]]; then
    return 0  # It is a loopback
  fi
  
  return 1  # Not a loopback
}

# Function to get ALL sink input IDs that match a pattern in name or binary (excluding loopbacks)
get_sink_input_ids_by_pattern() {
  local pattern=$1
  
  # Get all sink inputs and check each one
  pactl list sink-inputs short | awk '{print $1}' | while read id; do
    # Skip loopback modules
    if is_loopback_sink_input "$id"; then
      continue
    fi
    
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

# Function to move a specific sink input by ID (skip loopbacks)
move_sink_input_to_sink() {
  local sink_id=$1
  local sink_name=$2
  
  # Double-check it's not a loopback before moving
  if is_loopback_sink_input "$sink_id"; then
    return
  fi
  
  pactl move-sink-input "$sink_id" "$sink_name" 2>/dev/null
}

# Function to move ALL Wine/Proton games to Desktop (excluding loopbacks)
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

# Move specific applications by exact name or binary (excluding loopbacks)
move_application_to_sink() {
  local app_name=$1
  local sink_name=$2
  
  get_sink_input_ids_by_pattern "$app_name" | while read id; do
    if [ -n "$id" ]; then
      move_sink_input_to_sink "$id" "$sink_name"
    fi
  done
}

# Monitor for new applications (excluding loopbacks)
monitor_apps() {
  echo "=== Audio Monitor Started ===" | tee -a "$MONITOR_LOG_FILE"
  echo "Monitor PID: $$" | tee -a "$MONITOR_LOG_FILE"
  echo "Log file: $MONITOR_LOG_FILE" | tee -a "$MONITOR_LOG_FILE"
  echo "To stop: $0 --stop" | tee -a "$MONITOR_LOG_FILE"
  echo "================================" | tee -a "$MONITOR_LOG_FILE"
  
  # Process existing apps first (skip loopbacks)
  move_all_games_to_desktop
  move_application_to_sink "Chromium" "Music"
  move_application_to_sink "OBS" "Desktop"
  move_application_to_sink "WEBRTC VoiceEngine" "Discord"
  move_application_to_sink "Discord" "Discord"
  
  # Monitor for new sink inputs with auto-reconnect
  while true; do
    # Run pactl subscribe and process events
    pactl subscribe 2>/dev/null | while read event; do
      if echo "$event" | grep -q "sink-input"; then
        # New audio application appeared
        sleep 2  # Wait for app to fully initialize
        
        # Find the most recent sink input
        local new_sink_id=$(pactl list sink-inputs short | tail -1 | awk '{print $1}')
        
        if [ -n "$new_sink_id" ]; then
          # Skip if it's a loopback module
          if is_loopback_sink_input "$new_sink_id"; then
            continue
          fi
          
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
            echo "[$(date '+%H:%M:%S')] New app: $app_name → moving to $target_sink" | tee -a "$MONITOR_LOG_FILE"
            pactl move-sink-input "$new_sink_id" "$target_sink"
          fi
        fi
      fi
    done
    
    # If we get here, pactl subscribe died. Wait and restart
    echo "[$(date '+%H:%M:%S')] WARNING: Connection lost, restarting..." | tee -a "$MONITOR_LOG_FILE"
    sleep 5
  done
}

# Stop the monitor
stop_monitor() {
  if [ -f "$MONITOR_PID_FILE" ]; then
    local pid=$(cat "$MONITOR_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Stopping audio monitor (PID: $pid)"
      kill -TERM "$pid"
      # Wait for it to die
      for i in {1..5}; do
        if ! kill -0 "$pid" 2>/dev/null; then
          break
        fi
        sleep 1
      done
      # Force kill if needed
      if kill -0 "$pid" 2>/dev/null; then
        echo "Force killing monitor..."
        kill -9 "$pid"
      fi
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
      kill -TERM $pid
      echo "Monitor stopped"
    else
      echo "No running monitor found"
    fi
  fi
}

# Start the monitor as a daemon
start_daemon() {
  if [ -f "$MONITOR_PID_FILE" ]; then
    local pid=$(cat "$MONITOR_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Monitor already running (PID: $pid)"
      echo "Use '$0 --stop' to stop it first"
      exit 1
    else
      rm -f "$MONITOR_PID_FILE"
    fi
  fi
  
  echo "Starting audio monitor daemon..."
  # Start the monitor in background with nohup
  nohup "$0" --monitor > /dev/null 2>&1 &
  local pid=$!
  echo $pid > "$MONITOR_PID_FILE"
  echo "Monitor started with PID: $pid"
  echo "Log file: $MONITOR_LOG_FILE"
}

# Show status
show_status() {
  if [ -f "$MONITOR_PID_FILE" ]; then
    local pid=$(cat "$MONITOR_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Monitor is running (PID: $pid)"
      echo "Log file: $MONITOR_LOG_FILE"
      echo ""
      echo "Last 5 log entries:"
      tail -5 "$MONITOR_LOG_FILE" 2>/dev/null || echo "  No log entries yet"
    else
      echo "Monitor is not running (stale PID file)"
    fi
  else
    echo "Monitor is not running"
  fi
}

# Main execution
case "$1" in
  --monitor)
    # Internal use - run the actual monitor
    echo $$ > "$MONITOR_PID_FILE"
    monitor_apps
    ;;
  --start)
    start_daemon
    ;;
  --stop)
    stop_monitor
    ;;
  --restart)
    stop_monitor
    sleep 2
    start_daemon
    ;;
  --status)
    show_status
    ;;
  --logs)
    if [ -f "$MONITOR_LOG_FILE" ]; then
      tail -f "$MONITOR_LOG_FILE"
    else
      echo "No log file found"
    fi
    ;;
  --help)
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Daemon commands:"
    echo "  --start       Start the audio monitor as a daemon (auto-restarts)"
    echo "  --stop        Stop the daemon"
    echo "  --restart     Restart the daemon"
    echo "  --status      Show daemon status"
    echo "  --logs        Tail the log file"
    echo ""
    echo "One-time commands:"
    echo "  (no args)     Move all games and apps to correct sinks (once)"
    echo "  --help        Show this help"
    echo ""
    ;;
  *)
    # Default behavior: move everything (excluding loopbacks)
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
    echo ""
    echo "To start the auto-routing daemon (stays running forever):"
    echo "  $0 --start"
    ;;
esac
