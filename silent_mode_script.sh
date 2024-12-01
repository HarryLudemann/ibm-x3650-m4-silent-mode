#!/bin/bash

# Function to display status in a clean and user-friendly format
display_status() {
  local temperatures="$1"
  local max_temp="$2"
  local fan_speed="$3"

  echo "-------------------------------------------"
  echo " System Fan Control Status"
  echo "-------------------------------------------"
  echo "CPU Temperatures: $temperatures"
  echo "Maximum CPU Temperature: ${max_temp}°C"
  echo "Calculated Fan Speed: $fan_speed (0-255 scale)"
  echo "Fan Speed Hexadecimal: 0x$(printf '%02x' "$fan_speed")"
  echo "-------------------------------------------"
  echo "Last Updated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "-------------------------------------------"
}

# Function to get fan zones
get_fan_zones() {
  local output
  if ! output=$(ipmitool sdr 2>/dev/null); then
    echo "Error: Failed to retrieve IPMI sensor data."
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
  echo "Error: No fan zones found."
  exit 1
fi

# Temperature range for fan control
MIN_TEMP=30  # Minimum temperature
MAX_TEMP=80  # Maximum temperature

# Introduce a scaling factor (adjust between 0.0 and 1.0)
SCALING_FACTOR=0.3  # 70% of the calculated fan speed

while true; do
  # Get IPMI sensor data (temperature only)
  if ! ipmi_output=$(ipmitool sdr type temperature 2>/dev/null); then
    echo "Error: Failed to retrieve IPMI sensor data."
    sleep 5
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
    echo "Error: No CPU temperatures found."
    sleep 5
    continue
  fi

  # Find the maximum CPU temperature
  max_temp="${cpu_temps[0]}"
  for temp in "${cpu_temps[@]}"; do
    (( temp > max_temp )) && max_temp=$temp
  done

  # Calculate fan speed (0-255 scale)
  if (( max_temp <= MIN_TEMP )); then
    fan_speed=0
  elif (( max_temp >= MAX_TEMP )); then
    fan_speed=255
  else
    raw_speed=$(( (max_temp - MIN_TEMP) * 255 / (MAX_TEMP - MIN_TEMP) ))
    scaled_speed=$(echo "$raw_speed * $SCALING_FACTOR" | bc)
    fan_speed=${scaled_speed%.*}  # Remove decimal part
  fi

  # Ensure fan_speed is within 0-255
  if (( fan_speed < 0 )); then
    fan_speed=0
  elif (( fan_speed > 255 )); then
    fan_speed=255
  fi

  display_status "${cpu_temps[*]}" "$max_temp" "$fan_speed"

  # Convert fan speed to hexadecimal
  fan_speed_hex=$(printf '%02x' "$fan_speed")

  # Set fan speed for each applicable fan zone
  i=0
  for fan_zone in "${fan_zones[@]}"; do
    if [[ "$fan_zone" == *A ]]; then
      ((i++))
      sudo ipmitool raw 0x3a 0x07 0x0${i} 0x$fan_speed_hex 0x01 &> /dev/null
    fi
  done

  # Apply the changes
  sudo ipmitool raw 0x3a 0x06 &> /dev/null

  # Sleep to reduce CPU usage
  sleep 5
done
