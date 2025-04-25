# Felicity ESS 15kWh Battery Monitor Script

This Bash script connects to a **Felicity 15kWh battery**  
(**Model:** LUX-Y-48300LG01, 51.2V, 300Ah) and reads real-time data.  
The data is then published via MQTT to a specified broker.

The script is designed to run **once per minute via cronjob**.

## Setup

- The battery is **not connected to the house Wi-Fi**.
- A **Raspberry Pi** uses two Wi-Fi interfaces:
  - `wlan0` stays connected to your normal home network.
  - `wlan1` connects directly to the battery's Wi-Fi (static IP, no internet).
- The script handles Wi-Fi connection management automatically.

Example MQTT payload:

```json
{
  "battvoltage": "52.2",
  "battcurrent": "-0.6",
  "battsoc": "34",
  "bat_temp": "13.0",
  "cellvoltages": [3265, 3267, 3268, 3266, 3267, 3267, 3266, 3267, 3262, 3262, 3262, 3262, 3262, 3263, 3263, 3263]
}
