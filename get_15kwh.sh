#!/usr/bin/env bash

########################################
# Configuration
########################################

# VERBOSE: either "yes" or "no"
VERBOSE="no"

# Wi-Fi interface and network
INTF="wlan1"
CON_NAME="my-wlan1-connection"  # Arbitrary name for the connection
DEVICE_SSID="F10001100XXXXXXXXXX"
DEVICE_PSK="12345678"

# Static IP (no gateway, no DNS)
MY_STATIC_IP="192.168.155.10"  # Unused IP in the 192.168.155.x range
CIDR="24"                      # 255.255.255.0

# Server (Battery) info
SERVER_IP="192.168.155.1"
SERVER_PORT="53970"
# Only request 3 is used at the moment
REQUEST_3="wifilocalMonitor:get dev real infor"

# MQTT broker info
MQTT_HOST="192.168.1.2"
MQTT_PORT="1883"
MQTT_TOPIC="felicityess15kw1/topic"
MQTT_USER=""       # Optional username
MQTT_PASSWORD=""   # Optional password

########################################
# Helper function for conditional logging
########################################
log_info() {
  if [[ "$VERBOSE" == "yes" ]]; then
    echo "[INFO] $*"
  fi
}

log_error() {
  if [[ "$VERBOSE" == "yes" ]]; then
    echo "[ERROR] $*"
  fi
}

########################################
# Function: Connect via nmcli (Static IP)
########################################
connect_wifi() {
  log_info "Creating static IP connection '${CON_NAME}' on ${INTF}, no GW/DNS..."

  # Remove any old connection with the same name
  sudo nmcli connection delete "${CON_NAME}" >/dev/null 2>&1 || true

  # Add new Wi-Fi connection with static IPv4 (NO gateway, NO DNS)
  sudo nmcli connection add \
      type wifi \
      ifname "${INTF}" \
      con-name "${CON_NAME}" \
      ssid "${DEVICE_SSID}" \
      wifi-sec.key-mgmt wpa-psk \
      wifi-sec.psk "${DEVICE_PSK}" \
      ipv4.addresses "${MY_STATIC_IP}/${CIDR}" \
      ipv4.method manual

  log_info "Bringing up ${CON_NAME}..."
  sudo nmcli connection up "${CON_NAME}"
  sleep 3

  local ip_assigned
  ip_assigned=$(ip -4 addr show "${INTF}" | awk '/inet / {print $2}' | cut -d/ -f1)
  if [[ -z "$ip_assigned" ]]; then
    log_error "No IP address on ${INTF}."
    exit 1
  fi

  log_info "${INTF} is up with IP: ${ip_assigned}"
}

########################################
# Function: Check server reachability
########################################
check_server() {
  log_info "Pinging server at ${SERVER_IP}..."
  if ! ping -c 3 "${SERVER_IP}" >/dev/null 2>&1; then
    log_error "Server ${SERVER_IP} is unreachable. Exiting."
    disconnect_wifi
    exit 1
  fi
  log_info "Server ${SERVER_IP} is reachable."
}

########################################
# Function: Send request via netcat
########################################
send_request() {
  local request="$1"
  local response
  response=$(echo -e "$request" | nc -w 2 "$SERVER_IP" "$SERVER_PORT")
  echo "$response"
}

########################################
# Function: Extract battery info from JSON
########################################
extract_battery_info() {
  local json="$1"

  # ---------------------------
  # 1) Battery Voltage & Current
  # ---------------------------
  # Example: "Batt":[[53100],[-10],[null]]
  batt_raw=$(echo "$json" \
    | grep -o '"Batt":\[\[.*\]\]' \
    | sed 's|"Batt":\[\[\(.*\)\]\].*|\1|' \
    | tr -d '[]')

  # Battery voltage (mV -> V)
  battery_voltage=$(echo "$batt_raw" | awk -F, '{printf "%.1f", $1 / 1000}')

  # Battery current (raw -> A)
  # Example: -10 => -1.0 A
  battery_current_raw=$(echo "$batt_raw" | awk -F, '{print $2}')
  battery_current=$(echo "scale=1; $battery_current_raw / 10" | bc)
  # If battery_current starts with '.' or '-.', prepend 0
  battery_current=$(echo "$battery_current" | sed -E 's/^(-)?\./\10./')

  # ---------------------------
  # 2) Battery SoC
  # ---------------------------
  # Example: "Batsoc":[[4800,1000,300000]]
  batsoc_raw=$(echo "$json" \
    | grep -o '"Batsoc":\[\[.*\]\]' \
    | sed 's|"Batsoc":\[\[\(.*\)\]\].*|\1|' \
    | tr -d '[]')

  # Batsoc array => [4800,1000,300000]
  # SoC = 4800/100 => 48%
  batsoc_percentage=$(echo "$batsoc_raw" | awk -F, '{print $1 / 100}')

  # Max capacity (mAh -> Ah)
  # 300000 mAh => 300.0 Ah
  batsoc_max_raw=$(echo "$batsoc_raw" | awk -F, '{print $3}')
  batsoc_max_ah=$(echo "scale=1; $batsoc_max_raw / 1000" | bc)

  # Current capacity in Ah
  batsoc_current_ah=$(echo "scale=1; $batsoc_max_ah * $batsoc_percentage / 100" | bc)

  # ---------------------------
  # 3) Battery Temp (first value / 10)
  # ---------------------------
  # Example: "BTemp":[[70,60],[256,257]]
  # => first sub-array [70,60], first value = 70 => 70/10 => 7.0
  btemp_firstline=$(echo "$json" \
    | grep -oP '"BTemp":\[\[\K[^]]+' \
    || echo "")
  # btemp_firstline = "70,60" (for example)
  local btemp_raw
  btemp_raw=$(echo "$btemp_firstline" | cut -d',' -f1)  # => "70"
  if [[ -z "$btemp_raw" ]]; then
    bat_temp="0.0"  # fallback
  else
    # divide by 10 => e.g. 70 => 7.0
    bat_temp=$(awk "BEGIN {printf \"%.1f\", $btemp_raw / 10}")
  fi

  # ---------------------------
  # 4) Cell Voltages (first sub-array of "BatcelList")
  # ---------------------------
  # "BatcelList":[[3319,3318,3319,3320,...(16 cells total)...],[65535,65535,...]]
  # We'll parse the first 16 from the first sub-array
  local batcel_firstline
  batcel_firstline=$(echo "$json" \
    | grep -oP '"BatcelList":\[\[\K[^]]+' \
    || echo "")
  # batcel_firstline example => "3319,3318,3319,3320,..."

  # Convert to an array
  IFS=',' read -ra batcel_array <<< "$batcel_firstline"

  # We'll store up to 16 valid cell voltages (in mV) in an array for JSON
  local -a cellvoltages
  local i
  for (( i=0; i<16; i++ )); do
    # Make sure array index exists
    if [[ -n "${batcel_array[$i]}" ]]; then
      cellvoltages[$i]="${batcel_array[$i]}"
    else
      cellvoltages[$i]="null"
    fi
  done

  # Turn that array into a JSON array string
  # e.g. [3319,3318,3319,3320,...]
  cellvoltages_json="["
  for (( i=0; i<16; i++ )); do
    # If it's not the first element, add a comma
    if (( i > 0 )); then
      cellvoltages_json="${cellvoltages_json},"
    fi

    # If "null", just add null, else the numeric value
    if [[ "${cellvoltages[$i]}" == "null" ]]; then
      cellvoltages_json="${cellvoltages_json}null"
    else
      cellvoltages_json="${cellvoltages_json}${cellvoltages[$i]}"
    fi
  done
  cellvoltages_json="${cellvoltages_json}]"

  # Expose them as global variables
  export battery_voltage
  export battery_current
  export batsoc_percentage
  export batsoc_max_ah
  export batsoc_current_ah
  export bat_temp
  export cellvoltages_json
}

########################################
# Function: Disconnect Wi-Fi
########################################
disconnect_wifi() {
  log_info "Disconnecting Wi-Fi on ${INTF}..."
  sudo nmcli connection down "${CON_NAME}" >/dev/null 2>&1
  sudo nmcli connection delete "${CON_NAME}" >/dev/null 2>&1 || true
}

######################
# MQTT SEND FUNCTION #
######################
send_mqtt_message() {
  local message="$1"
  mosquitto_pub \
    -h "$MQTT_HOST" \
    -p "$MQTT_PORT" \
    -t "$MQTT_TOPIC" \
    -m "$message" \
    --username "$MQTT_USER" \
    --pw "$MQTT_PASSWORD"
}

########################################
# Main Workflow
########################################

# 1) Connect to the battery wifi via WLAN1 (static IP, no GW/DNS)
connect_wifi

# 2) Check server (ping the battery)
check_server

# 3) Fetch battery information
log_info "Fetching battery information..."
answer3=$(send_request "$REQUEST_3")

# 4) Process battery information
log_info "Processing battery information from answer3..."
extract_battery_info "$answer3"

# Show raw JSON if VERBOSE="yes"
if [[ "$VERBOSE" == "yes" ]]; then
  echo "[DEBUG] Raw JSON from device:"
  echo "$answer3"
fi

# 5) Print final info (always shown, even if VERBOSE="no")
#echo "Battery Voltage: $battery_voltage V"
#echo "Battery Current: $battery_current A"
#echo "Battery State of Charge (SoC): ${batsoc_percentage}%"
#echo "Current Capacity: $batsoc_current_ah Ah"
#echo "Maximum Capacity: $batsoc_max_ah Ah"
#echo "Battery Temperature: $bat_temp °C"
#echo "Cell Voltages (mV): $cellvoltages_json"

# 6) Disconnect
disconnect_wifi

# 7) Publish info via MQTT
# Build a JSON string containing everything, including temp + cell voltages
MESSAGE="{\"battvoltage\":\"$battery_voltage\",\"battcurrent\":\"$battery_current\",\"battsoc\":\"$batsoc_percentage\",\"bat_temp\":\"$bat_temp\",\"cellvoltages\":$cellvoltages_json}"
send_mqtt_message "$MESSAGE"


# Done
