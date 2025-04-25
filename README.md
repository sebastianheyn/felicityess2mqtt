# Felicity ESS 15kWh Battery Monitor Script

This Bash script connects to a **Felicity 15kWh battery**  
(**Model:** LUX-Y-48300LG01, 51.2V, 300Ah) and reads real-time data.  
The data is then published via MQTT to a specified broker.

The script is designed to run **once per minute via cronjob**.

## Setup

- The battery is **not connected to the house LAN Wi-Fi**.
- A **Raspberry Pi** uses two Wi-Fi interfaces:
  - `wlan0` stays connected to your normal home network.
  - `wlan1` connects directly to the battery's Wi-Fi (static IP, no internet).
- The script handles Wi-Fi connection management automatically.
- I have put the script into /usr/local/bin/

## Technical Background

The structure of the battery's communication protocol was reverse-engineered  
by capturing and analyzing network traffic between the **Felicity mobile app** and the battery.

By inspecting the transmitted packets, I was able to reconstruct the  
correct request string and parse the JSON-like response format.

Example MQTT payload created by the script and sent to your MQTT server:

```json
{
  "battvoltage": "52.2",
  "battcurrent": "-0.6",
  "battsoc": "34",
  "bat_temp": "13.0",
  "cellvoltages": [3265, 3267, 3268, 3266, 3267, 3267, 3266, 3267, 3262, 3262, 3262, 3262, 3262, 3263, 3263, 3263]
}
