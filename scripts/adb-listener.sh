#!/bin/bash

HA_URL="http://YOUR_HA_IP:8123"
HA_TOKEN="YOUR_LONG_LIVED_ACCESS_TOKEN"
TV_IP="YOUR_TV_IP"
LED_LEISTE="light.YOUR_LIGHT_ENTITY_1"
LED_UNTERBAU="light.YOUR_LIGHT_ENTITY_2"

STATE_DIR="/tmp/adb-listener"
mkdir -p "$STATE_DIR"
echo "up" > "$STATE_DIR/green_dir"
echo "up" > "$STATE_DIR/yellow_dir"
touch "$STATE_DIR/stop_bg"

HOLD_MS=600

call_ha() {
    curl -s -X POST "${HA_URL}/api/services/$1" \
        -H "Authorization: Bearer ${HA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$2" > /dev/null
}

get_brightness() {
    curl -s "${HA_URL}/api/states/$1" \
        -H "Authorization: Bearer ${HA_TOKEN}" | \
        python3 -c "import json,sys; d=json.load(sys.stdin); print(int(d['attributes'].get('brightness', 128)))" 2>/dev/null || echo "128"
}

stop_bg() {
    touch "$STATE_DIR/stop_bg"
    sleep 0.15
}

dim_loop() {
    local entity="$1"
    local direction="$2"
    while [ ! -f "$STATE_DIR/stop_bg" ]; do
        brightness=$(get_brightness "$entity")
        if [ "$direction" = "up" ]; then
            new=$(( brightness + 18 ))
            [ $new -gt 255 ] && new=255
        else
            new=$(( brightness - 18 ))
            [ $new -lt 3 ] && new=3
        fi
        call_ha "light/turn_on" "{\"entity_id\": \"${entity}\", \"brightness\": ${new}}"
        sleep 0.35
    done
}

disco_loop() {
    local colors=("255,0,0" "255,140,0" "255,255,0" "0,255,0" "0,0,255" "138,43,226" "255,0,255")
    local i=0
    while [ ! -f "$STATE_DIR/stop_bg" ]; do
        call_ha "light/turn_on" "{\"entity_id\": \"${LED_LEISTE}\", \"rgb_color\": [${colors[$i]}], \"brightness\": 255}"
        i=$(( (i + 1) % ${#colors[@]} ))
        sleep 0.4
    done
}

start_bg() {
    rm -f "$STATE_DIR/stop_bg"
    "$@" &
}

connect_tv() {
    adb connect "${TV_IP}:5555" > /dev/null 2>&1
    sleep 2
}

flip_dir() {
    local file="$1"
    local current
    current=$(cat "$file")
    [ "$current" = "up" ] && echo "down" > "$file" || echo "up" > "$file"
}

echo "$(date): ADB Listener gestartet"
connect_tv

RED_DOWN=0; GREEN_DOWN=0; BLUE_DOWN=0; YELLOW_DOWN=0
GREEN_TIMER_PID=""; YELLOW_TIMER_PID=""

while true; do
    while read -r line; do
        now=$(date +%s%3N)

        if echo "$line" | grep -q "KEY_RED.*DOWN"; then
            RED_DOWN=$now
        elif echo "$line" | grep -q "KEY_RED.*UP"; then
            dur=$(( now - RED_DOWN ))
            if [ $dur -lt $HOLD_MS ]; then
                echo "$(date): ROT Kurz - Alles aus"
                stop_bg
                call_ha "light/turn_off" "{\"entity_id\": [\"${LED_LEISTE}\", \"${LED_UNTERBAU}\"]}"
            fi

        elif echo "$line" | grep -q "KEY_GREEN.*DOWN"; then
            GREEN_DOWN=$now
            GREEN_DIR=$(cat "$STATE_DIR/green_dir")
            stop_bg
            kill $GREEN_TIMER_PID 2>/dev/null
            (
                sleep $(echo "scale=3; $HOLD_MS/1000" | bc)
                rm -f "$STATE_DIR/stop_bg"
                dim_loop "$LED_LEISTE" "$GREEN_DIR" &
                dim_loop "$LED_UNTERBAU" "$GREEN_DIR" &
                wait
            ) &
            GREEN_TIMER_PID=$!
        elif echo "$line" | grep -q "KEY_GREEN.*UP"; then
            dur=$(( now - GREEN_DOWN ))
            if [ $dur -lt $HOLD_MS ]; then
                echo "$(date): GRUEN Kurz - Alles an"
                kill $GREEN_TIMER_PID 2>/dev/null; GREEN_TIMER_PID=""
                stop_bg
                call_ha "light/turn_on" "{\"entity_id\": \"${LED_LEISTE}\", \"brightness_pct\": 100, \"rgb_color\": [255, 197, 143]}"
                call_ha "light/turn_on" "{\"entity_id\": \"${LED_UNTERBAU}\", \"brightness_pct\": 100}"
            else
                echo "$(date): GRUEN Lang Ende - Stopp, Richtung flip"
                stop_bg; flip_dir "$STATE_DIR/green_dir"
            fi

        elif echo "$line" | grep -q "KEY_BLUE.*DOWN"; then
            BLUE_DOWN=$now
        elif echo "$line" | grep -q "KEY_BLUE.*UP"; then
            dur=$(( now - BLUE_DOWN ))
            if [ $dur -lt $HOLD_MS ]; then
                echo "$(date): BLAU Kurz - Rickroll + Disco"
                stop_bg
                adb -s "${TV_IP}:5555" shell am start -n "org.smarttube.stable/com.liskovsoft.smartyoutubetv2.tv.ui.main.SplashActivity" \
                    -a android.intent.action.VIEW \
                    -d "https://www.youtube.com/watch?v=dQw4w9WgXcQ" > /dev/null 2>&1
                start_bg disco_loop
            fi

        elif echo "$line" | grep -q "KEY_YELLOW.*DOWN"; then
            YELLOW_DOWN=$now
            YELLOW_DIR=$(cat "$STATE_DIR/yellow_dir")
            stop_bg
            kill $YELLOW_TIMER_PID 2>/dev/null
            (
                sleep $(echo "scale=3; $HOLD_MS/1000" | bc)
                rm -f "$STATE_DIR/stop_bg"
                dim_loop "$LED_LEISTE" "$YELLOW_DIR" &
                wait
            ) &
            YELLOW_TIMER_PID=$!
        elif echo "$line" | grep -q "KEY_YELLOW.*UP"; then
            dur=$(( now - YELLOW_DOWN ))
            if [ $dur -lt $HOLD_MS ]; then
                echo "$(date): GELB Kurz - Filmabend"
                kill $YELLOW_TIMER_PID 2>/dev/null; YELLOW_TIMER_PID=""
                stop_bg
                call_ha "light/turn_on" "{\"entity_id\": \"${LED_LEISTE}\", \"brightness_pct\": 20, \"rgb_color\": [255, 147, 41]}"
                call_ha "light/turn_off" "{\"entity_id\": \"${LED_UNTERBAU}\"}"
            else
                echo "$(date): GELB Lang Ende - Stopp, Richtung flip"
                stop_bg; flip_dir "$STATE_DIR/yellow_dir"
            fi
        fi

    done < <(adb -s "${TV_IP}:5555" shell getevent -l 2>/dev/null)

    echo "$(date): Verbindung unterbrochen, reconnect..."
    stop_bg
    sleep 3
    connect_tv
done
