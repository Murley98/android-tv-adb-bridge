# android-tv-adb-bridge

Control smart home devices using your Android TV remote — no extra hardware required.

This project uses ADB (Android Debug Bridge) over the network to intercept IR remote button events directly on the TV and forward them to Home Assistant via its REST API.

## Why does this exist?

When your TV is connected to an AV receiver via **optical cable (TOSLINK/S/PDIF)**, there is no HDMI ARC/eARC and therefore no CEC. This means:

- The TV remote's volume buttons only control the TV's own internal volume — not the AVR
- There's no native way to pass IR signals from the remote to external devices

This project solves that by running a persistent ADB listener on a small Linux machine (e.g. a Proxmox LXC container, Raspberry Pi, or any always-on Linux box) that captures those IR events and bridges them to Home Assistant.

---

## Features

### 1. Light Control (`adb-listener.sh`)
Intercepts the **color buttons** (Red / Green / Blue / Yellow) on the TV remote and controls HA-integrated lights.

| Button | Short press | Long press |
|--------|------------|------------|
| Red    | All lights off | — |
| Green  | All lights on (warm white) | Start dimming (direction toggles each long press) |
| Yellow | Movie mode (dim warm) | Start dimming single light |
| Blue   | Custom action (disco mode by default) | — |

Short vs. long press is distinguished by a configurable hold threshold (`HOLD_MS`, default 600ms).

### 2. Volume Bridge (`tv-volume-bridge.sh`)
Intercepts **VOL+ / VOL−** buttons and forwards them to a media player entity in Home Assistant (e.g. a Denon AVR). After each press, it queries the current volume level and triggers a pixel-art overlay on the TV showing the volume in dB.

```
TV remote (IR)
  → ADB getevent (event1)
  → Home Assistant REST API (media_player.volume_up / volume_down)
  → Denon AVR (or any HA media_player entity)
  → ADB: launch volume overlay app on TV
```

### 3. Web Gamepad (`gamepad/`)
A Python WebSocket server + HTML touch controller that creates a virtual uinput gamepad on the host. Useful for streaming setups (e.g. Sunshine/Moonlight) where you want to use a phone as a controller.

- Serves the touch UI on port **8080**
- WebSocket on port **8765**
- Creates a `/dev/uinput` virtual gamepad (D-Pad, ABXY, L/R, Select/Start)

---

## Requirements

- Linux machine with **ADB** installed (`apt install adb`)
- Android TV with **ADB over network enabled** (Developer Options → USB debugging / ADB over network)
- Home Assistant with a long-lived access token
- `curl`, `python3`, `bc` on the Linux machine

For the web gamepad:
- `python3-evdev`, `python3-websockets` (`pip3 install evdev websockets`)
- `/dev/uinput` access (either as root or with appropriate group/cgroup permissions)

---

## Setup

### 1. Enable ADB on your Android TV

On your TV: **Settings → Device Preferences → Developer Options → Network Debugging → On**

Verify connectivity from your Linux machine:
```bash
adb connect YOUR_TV_IP:5555
adb devices
```

### 2. Find the correct input device for volume keys

```bash
adb -s YOUR_TV_IP:5555 shell getevent -l
# Press VOL+ and watch which /dev/input/eventX shows KEY_VOLUMEUP
```

Update the `event1` reference in `tv-volume-bridge.sh` if your device is different.

### 3. Configure the scripts

Edit the variables at the top of each script:

**`adb-listener.sh`:**
```bash
HA_URL="http://YOUR_HA_IP:8123"
HA_TOKEN="YOUR_LONG_LIVED_ACCESS_TOKEN"
TV_IP="YOUR_TV_IP"
LED_LEISTE="light.YOUR_LIGHT_ENTITY_1"
LED_UNTERBAU="light.YOUR_LIGHT_ENTITY_2"
```

**`tv-volume-bridge.sh`:**
```bash
TV_ADB=YOUR_TV_IP:5555
HA_URL=http://YOUR_HA_IP:8123
HA_TOKEN=YOUR_LONG_LIVED_ACCESS_TOKEN
ENTITY=media_player.YOUR_AVR_ENTITY
```

A long-lived access token can be created in Home Assistant under:  
**Profile → Security → Long-Lived Access Tokens**

### 4. Install as systemd services

```bash
# Copy scripts
cp scripts/adb-listener.sh /usr/local/bin/
cp scripts/tv-volume-bridge.sh /usr/local/bin/
chmod +x /usr/local/bin/adb-listener.sh /usr/local/bin/tv-volume-bridge.sh

# Install services
cp systemd/adb-listener.service /etc/systemd/system/
cp systemd/tv-volume-bridge.service /etc/systemd/system/

# Enable and start
systemctl daemon-reload
systemctl enable --now adb-listener.service
systemctl enable --now tv-volume-bridge.service
```

---

## Volume Overlay App

The `tv-volume-bridge.sh` script expects an Android app installed on the TV that displays the current volume as a pixel-art overlay:

```
adb shell am start -n com.simonmurr.volumeoverlay/.OverlayActivity --ef volume_db -42.5
```

The app launches as a transparent overlay, shows the dB value, and auto-dismisses after a few seconds. The APK is available in the [Releases](../../releases) section.

The dB value is calculated from the HA `volume_level` attribute (0.0–1.0) using the Denon AVR scale:
```
dB = volume_level × 98 − 80
```
Adjust this formula in `get_volume_db()` for other AVR brands.

---

## Running on a Proxmox LXC container

A minimal Debian/Ubuntu LXC container works well. Recommended specs:
- 1 CPU core, 256 MB RAM
- Unprivileged container is fine

Make sure the container starts on boot and the services are enabled. The scripts handle ADB reconnection automatically if the TV reboots or the connection drops.

---

## License

MIT
