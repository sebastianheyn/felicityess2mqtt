# Felicity ESS 15kWh Battery Monitor Script

This Bash script connects to a **Felicity 15kWh battery**  
(**Model:** LUX-Y-48300LG01, 51.2V, 300Ah) and reads real-time data.  
The data is then published via MQTT to a specified broker.

The script is designed to run **once per minute via cronjob**.

---

## Setup

- The battery is **not connected to the house LAN Wi-Fi**.
- A **Raspberry Pi** uses two Wi-Fi interfaces:
  - `wlan0` stays connected to your normal home network.
  - `wlan1` connects directly to the battery's Wi-Fi (static IP, no internet).
- The script handles Wi-Fi connection management automatically.
- I have put the script into /usr/local/bin/

---
## Features

- Sets up and connects `wlan1` to the battery's Wi-Fi network using a static IP (no gateway).
- Requests real-time battery status via TCP connection and parses the data.
- Publishes the extracted values (voltage, current, SoC, temperature, cell voltages) to an MQTT broker.

---

## Dependencies

This script was developed and tested on **Debian 12.6** (Raspberry Pi).  
It requires the following tools to be installed:

- `nmcli` (for Wi-Fi management) → package: `network-manager`
- `mosquitto-clients` (for MQTT publishing) → package: `mosquitto-clients`
- `netcat-openbsd` (for sending TCP requests) → package: `netcat-openbsd`
- `bc` (for floating-point calculations) → package: `bc`

You can install all dependencies with:

sudo apt update && sudo apt install network-manager mosquitto-clients netcat-openbsd bc

---

## Technical Background

The structure of the battery's communication protocol was reverse-engineered  
by capturing and analyzing network traffic between the **Felicity mobile app** and the battery.

By inspecting the transmitted packets, I was able to reconstruct the  
correct request string and parse the JSON-like response format.

---

Example MQTT payload created by the script and sent to your MQTT server:

```json
{
  "battvoltage": "52.2",
  "battcurrent": "-0.6",
  "battsoc": "34",
  "bat_temp": "13.0",
  "cellvoltages": [3265, 3267, 3268, 3266, 3267, 3267, 3266, 3267, 3262, 3262, 3262, 3262, 3262, 3263, 3263, 3263]
}
