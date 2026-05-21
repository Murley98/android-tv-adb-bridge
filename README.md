# android-tv-adb-bridge

Bridge Android TV IR remote volume buttons to Home Assistant via ADB — control your AVR over optical cable without HDMI CEC.

## Why does this exist?

Modern TVs sometimes output audio formats (e.g. Dolby Atmos, TrueHD) that older AV receivers cannot decode over HDMI ARC — resulting in no sound or audio glitches. The common fix is to switch to an **optical cable (TOSLINK/S/PDIF)**, which carries a signal the receiver can handle. However, optical cable has no CEC, so:

- The TV remote's volume buttons only control the TV's own internal volume — not the AVR
- There's no native way to pass those IR signals to external devices

### Why not an HDMI splitter?

An HDMI splitter (e.g. Feintech) can in theory strip the audio to optical while keeping CEC alive on the HDMI side. In practice this doesn't always work reliably, and may not be worth the added complexity.

### What about remapping volume keys on the TV?

On some Android TV models it's possible to remap the volume buttons or intercept the key events internally via ADB before the TV processes them — which would avoid the TV's own volume bar appearing on screen. However, this is highly device-specific and doesn't work on all models (e.g. certain TCL TVs don't expose this). If you want to explore it, `adb shell` + `input keyevent` remapping or `getevent`-based interception are the starting points.

### What about CEC for power control?

You can still run an HDMI cable alongside the optical cable purely for CEC — this allows the TV to turn the receiver on/off automatically. If your setup doesn't support CEC at all, the same ADB listener approach used here could be extended to intercept power button events and trigger the receiver via Home Assistant.

This project solves the volume problem by running a persistent ADB listener on a small Linux machine (e.g. a Proxmox LXC container, Raspberry Pi, or any always-on Linux box) that captures volume key events and forwards them to Home Assistant, which then controls the AVR.

---

## Features

### Volume Bridge (`tv-volume-bridge.sh`)

Intercepts **VOL+ / VOL−** on the TV remote and forwards them to a media player entity in Home Assistant (e.g. a Denon AVR). After each press, it queries the current volume level and optionally triggers a pixel-art overlay on the TV showing the volume in dB.

```
TV remote (IR)
  → ADB getevent
  → Home Assistant REST API (media_player.volume_up / volume_down)
  → AVR (any HA media_player entity)
  → ADB: launch volume overlay app on TV  [optional]
```

---

## Requirements

- Linux machine with **ADB** installed (`apt install adb`)
- Android TV with **ADB over network enabled** (Developer Options → Network Debugging)
- Home Assistant with a long-lived access token
- `curl`, `python3` on the Linux machine

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

## Volume Overlay App (optional)

The script can optionally launch a pixel-art volume overlay on the TV after each key press. The overlay displays the current volume in dB, auto-dismisses after a few seconds, and has no UI chrome — it appears as a clean floating indicator on top of whatever is playing.

> The overlay app is entirely optional. If you don't install it, simply remove the `show_overlay` call from the script and everything else works the same.

The APK is available in the [Releases](../../releases) section.

It is triggered via:
```bash
adb shell am start -n com.simonmurr.volumeoverlay/.OverlayActivity --ef volume_db -42.5
```

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
