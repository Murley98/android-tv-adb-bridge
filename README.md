# android-tv-adb-bridge

Bridge Android TV IR remote volume buttons to Home Assistant via ADB — control your AVR over optical cable without HDMI CEC.

## Why does this exist?

When your TV is connected to an AV receiver via **optical cable (TOSLINK/S/PDIF)**, there is no HDMI ARC/eARC and therefore no CEC. This means:

- The TV remote's volume buttons only control the TV's own internal volume — not the AVR
- There's no native way to pass IR signals from the remote to external devices

This project solves that by running a persistent ADB listener on a small Linux machine (e.g. a Proxmox LXC container, Raspberry Pi, or any always-on Linux box) that captures volume key events and forwards them to Home Assistant, which then controls the AVR.

---

## Features

### Volume Bridge (`tv-volume-bridge.sh`)

Intercepts **VOL+ / VOL−** on the TV remote and forwards them to a media player entity in Home Assistant (e.g. a Denon AVR). After each press, it queries the current volume level and triggers a pixel-art overlay on the TV showing the volume in dB.

```
TV remote (IR)
  → ADB getevent
  → Home Assistant REST API (media_player.volume_up / volume_down)
  → AVR (any HA media_player entity)
  → ADB: launch volume overlay app on TV
```

### Web Gamepad (`gamepad/`)

A Python WebSocket server + HTML touch controller that creates a virtual uinput gamepad on the host. Useful for streaming setups (e.g. Sunshine/Moonlight) where you want to use a phone as a controller.

- Serves the touch UI on port **8080**
- WebSocket on port **8765**
- Creates a `/dev/uinput` virtual gamepad (D-Pad, ABXY, L/R, Select/Start)

---

## Requirements

- Linux machine with **ADB** installed (`apt install adb`)
- Android TV with **ADB over network enabled** (Developer Options → Network Debugging)
- Home Assistant with a long-lived access token
- `curl`, `python3` on the Linux machine

For the web gamepad:
- `python3-evdev`, `python3-websockets` (`pip3 install evdev websockets`)
- `/dev/uinput` access (either as root or with appropriate cgroup permissions)

---

## Setup

### 1. Enable ADB on your Android TV

**Settings → Device Preferences → Developer Options → Network Debugging → On**

Verify connectivity:
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

### 3. Configure the script

Edit the variables at the top of `tv-volume-bridge.sh`:

```bash
TV_ADB=YOUR_TV_IP:5555
HA_URL=http://YOUR_HA_IP:8123
HA_TOKEN=YOUR_LONG_LIVED_ACCESS_TOKEN
ENTITY=media_player.YOUR_AVR_ENTITY
```

A long-lived access token can be created in Home Assistant under:  
**Profile → Security → Long-Lived Access Tokens**

### 4. Install as a systemd service

```bash
cp scripts/tv-volume-bridge.sh /usr/local/bin/
chmod +x /usr/local/bin/tv-volume-bridge.sh

cp systemd/tv-volume-bridge.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now tv-volume-bridge.service
```

---

## Volume Overlay App

`tv-volume-bridge.sh` expects an Android app installed on the TV that displays the current volume as a pixel-art overlay:

```
adb shell am start -n com.simonmurr.volumeoverlay/.OverlayActivity --ef volume_db -42.5
```

The app launches as a transparent overlay, shows the dB value, and auto-dismisses after a few seconds. The APK is available in the [Releases](../../releases) section.

The dB value is calculated from the HA `volume_level` attribute (0.0–1.0) using the Denon AVR scale:
```
dB = volume_level × 98 − 80
```
Adjust the formula in `get_volume_db()` for other AVR brands.

---

## Running on a Proxmox LXC container

A minimal Debian/Ubuntu LXC container works well. Recommended specs:
- 1 CPU core, 256 MB RAM
- Unprivileged container

The script handles ADB reconnection automatically if the TV reboots or the connection drops.

---

## License

MIT
