#!/bin/bash

# Function to get fan zones
get_fan_zones() {
  local output
  if ! output=$(ipmitool sdr 2>/dev/null); then
    echo "Error: Failed to retrieve IPMI sensor data." >&2
    exit 1
  fi

  local zones=()
  while IFS= read -r line; do
    if [[ $line =~ ^Fan\ ([0-9][A-Z])\ Tach ]]; then
      zones+=("${BASH_REMATCH[1]}")
    fi
  done <<< "$output"
  echo "${zones[@]}"
}

# Get fan zones at the beginning
fan_zones=($(get_fan_zones))
if [[ ${#fan_zones[@]} -eq 0 ]]; then
  echo "Error: No fan zones found." >&2
  exit 1
fi

# Temperature range for fan control
MIN_TEMP=30  # Minimum temperature
MAX_TEMP=80  # Maximum temperature

# Scaling factor for fan control
SCALING_FACTOR=0.2  # 20% of the calculated fan speed

# Hysteresis settings
HYSTERESIS=2  # Temperature difference to avoid rapid fan speed changes

# Reduce update frequency to save CPU
SLEEP_INTERVAL=15  # Update every 15 seconds

# Previous fan speed to apply hysteresis
prev_fan_speed=-1

while true; do
  # Get IPMI sensor data (temperature only)
  if ! ipmi_output=$(ipmitool sdr type temperature 2>/dev/null); then
    echo "Warning: Failed to retrieve IPMI sensor data." >&2
    sleep $SLEEP_INTERVAL
    continue
  fi

  # Extract CPU temperatures
  cpu_temps=()
  while IFS= read -r line; do
    if [[ $line == *"CPU"* && $line == *"Temp"* ]]; then
      temp=$(echo "$line" | awk -F'|' '{print $5}' | sed 's/[^0-9.]//g')
      if [[ -n $temp ]]; then
        cpu_temps+=("$temp")
      fi
    fi
  done <<< "$ipmi_output"

  if [[ ${#cpu_temps[@]} -eq 0 ]]; then
    echo "Warning: No CPU temperatures found." >&2
    sleep $SLEEP_INTERVAL
    continue
  fi

  # Find the maximum CPU temperature
  max_temp="${cpu_temps[0]}"
  for temp in "${cpu_temps[@]}"; do
    (( temp > max_temp )) && max_temp=$temp
  done

  # Calculate fan speed using a non-linear (cubic) curve
  if (( max_temp <= MIN_TEMP )); then
    fan_speed=0
  elif (( max_temp >= MAX_TEMP )); then
    fan_speed=255
  else
    # Cubic scaling for smoother fan speed control
    temp_ratio=$(echo "scale=4; ($max_temp - $MIN_TEMP) / ($MAX_TEMP - $MIN_TEMP)" | bc)
    raw_speed=$(echo "scale=0; 255 * ($temp_ratio ^ 3)" | bc)
    scaled_speed=$(echo "$raw_speed * $SCALING_FACTOR" | bc)
    fan_speed=${scaled_speed%.*}  # Remove decimal part
  fi

  # Ensure fan_speed is within 0-255
  if (( fan_speed < 0 )); then
    fan_speed=0
  elif (( fan_speed > 255 )); then
    fan_speed=255
  fi

  # Apply hysteresis to prevent rapid fan changes
  if (( prev_fan_speed != -1 )); then
    if (( fan_speed > prev_fan_speed && fan_speed - prev_fan_speed < HYSTERESIS )); then
      fan_speed=$prev_fan_speed
    elif (( fan_speed < prev_fan_speed && prev_fan_speed - fan_speed < HYSTERESIS )); then
      fan_speed=$prev_fan_speed
    fi
  fi

  # Convert fan speed to hexadecimal
  fan_speed_hex=$(printf '%02x' "$fan_speed")

  # Set fan speed for each applicable fan zone
  i=0
  for fan_zone in "${fan_zones[@]}"; do
    if [[ "$fan_zone" == *A ]]; then
      ((i++))
      ipmitool raw 0x3a 0x07 0x0${i} 0x$fan_speed_hex 0x01 &> /dev/null
    fi
  done

  # Apply the changes
  ipmitool raw 0x3a 0x06 &> /dev/null

  # Store the previous fan speed
  prev_fan_speed=$fan_speed

  # Sleep to reduce CPU usage
  sleep $SLEEP_INTERVAL
done
