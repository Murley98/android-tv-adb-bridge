# android-tv-adb-bridge

Bridge Android TV IR remote volume buttons to Home Assistant via ADB — control your AVR over optical cable without HDMI CEC.

## Why does this exist?

Modern TVs sometimes output audio formats (e.g. Dolby Atmos, TrueHD) that older AV receivers cannot decode over HDMI ARC — resulting in no sound or audio glitches. The common fix is to switch to an **optical cable (TOSLINK/S/PDIF)**, which carries a signal the receiver can handle. However, optical cable has no CEC, so:

- The TV remote's volume buttons get blocked entirely — the TV neither controls the AVR nor its own internal audio
- There's no native way to pass those IR signals to external devices

### Alternatives I considered (and why I didn't use them)

**Universal remote:** The classic solution — program a universal remote to control the AVR directly. Didn't work for me because the receiver sits in a closed cabinet with no line of sight for IR, and I didn't want to buy an IR blaster just for this. Also, this approach is way cooler.

**HDMI splitter:** There are devices (e.g. from Feintech) that re-encode the HDMI ARC signal to an older Dolby format the receiver can handle, while keeping CEC intact. I bought one — it didn't work for me, and I didn't want to spend more money trying different models.

### What about CEC?

You can still run an HDMI cable alongside the optical cable purely for CEC. On/off control of the receiver should still work this way. However, **volume control via CEC is blocked** — at least on my TV, once the audio output is set to optical, the TV intercepts volume key presses and doesn't pass them through CEC anymore. That's exactly the problem this project solves.

If CEC doesn't work at all on your setup, the same ADB listener approach used here could be extended to intercept power button events and trigger the receiver via Home Assistant.

### Known limitation: native TV overlays

At least on my TCL model, two overlays from the TV itself cannot be suppressed:
- The native volume bar (even though the TV isn't actually changing any volume)
- A notification saying that volume control via optical is not supported

I tried removing them via key remapping and by intercepting the volume signal internally via ADB before the TV processes it — neither worked. If you've found a solution for this, feel free to open an issue or PR.

---

## How it works

```
TV remote (IR)
  → ADB getevent
  → Home Assistant REST API (media_player.volume_up / volume_down)
  → AVR (any HA media_player entity)
  → ADB: launch volume overlay app on TV  [optional]
```

A persistent ADB listener runs on a small Linux machine (e.g. a Proxmox LXC container, Raspberry Pi, or any always-on Linux box). It captures volume key events from the TV and forwards them to Home Assistant, which controls the AVR.

### Optional: auto-setup receiver on TV power-on

Some AVRs need a nudge after being switched on — e.g. setting the correct input source and sound mode — before they output audio. Triggering this from a Home Assistant automation based on the AVR's own state can be slow (state updates from the receiver can take up to 30 seconds).

Since the ADB connection drops when the TV turns off and re-establishes when it turns back on, the script uses this as a reliable and instant proxy for "TV just turned on". On every reconnect it waits a configurable number of seconds, then sets source, sound mode and volume via the HA API.

This is optional and disabled by default if you remove the `setup_receiver` call. Configure it at the top of the script:

```bash
STARTUP_DELAY=5      # seconds to wait before sending commands
STARTUP_VOLUME=0.5   # volume level 0.0–1.0 to set on startup
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

> The overlay app is entirely optional. If you don't want it, simply remove the `show_overlay` call from the script — everything else works the same.

Download the APK from the [Releases](../../releases) section and install it via ADB:

```bash
adb -s YOUR_TV_IP:5555 install volumeoverlay.apk
```

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
