#!/bin/bash

TV_ADB=YOUR_TV_IP:5555
HA_URL=http://YOUR_HA_IP:8123
HA_TOKEN=YOUR_LONG_LIVED_ACCESS_TOKEN
ENTITY=media_player.YOUR_AVR_ENTITY

# How long to wait after TV connects before setting up the receiver (seconds)
STARTUP_DELAY=5
# Volume to set on startup (0.0 – 1.0)
STARTUP_VOLUME=0.5

call_ha() {
    local service=$1
    local data=${2:-"{\"entity_id\": \"$ENTITY\"}"}
    curl -s -o /dev/null -X POST \
        -H "Authorization: Bearer $HA_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$data" \
        "$HA_URL/api/services/media_player/$service"
}

get_volume_db() {
    local level
    level=$(curl -s \
        -H "Authorization: Bearer $HA_TOKEN" \
        "$HA_URL/api/states/$ENTITY" \
        | grep -o '"volume_level":[0-9.]*' | cut -d: -f2)
    echo "$level" | awk '{printf "%.1f", $1 * 98 - 80}'
}

show_overlay() {
    local db=$1
    adb -s $TV_ADB shell am start -n com.simonmurr.volumeoverlay/.OverlayActivity \
        --ef volume_db "$db" > /dev/null 2>&1 &
}

setup_receiver() {
    sleep $STARTUP_DELAY
    echo "$(date): TV turned on - setting up receiver..."
    call_ha "select_source" "{\"entity_id\": \"$ENTITY\", \"source\": \"TV\"}"
    sleep 1
    call_ha "select_sound_mode" "{\"entity_id\": \"$ENTITY\", \"sound_mode\": \"AUTO\"}"
    sleep 1
    call_ha "volume_set" "{\"entity_id\": \"$ENTITY\", \"volume_level\": $STARTUP_VOLUME}"
    echo "$(date): Receiver ready"
}

connect_tv() {
    adb connect $TV_ADB > /dev/null 2>&1
    sleep 2
}

echo "$(date): TV Volume Bridge started"
connect_tv
FIRST_RUN=1

while true; do
    # On reconnect (not first start) the TV just turned on → set up receiver
    if [ $FIRST_RUN -eq 0 ]; then
        setup_receiver &
    fi
    FIRST_RUN=0

    adb -s $TV_ADB shell getevent -l /dev/input/event1 2>/dev/null | while read -r line; do
        if echo "$line" | grep -q "KEY_VOLUMEUP.*DOWN"; then
            call_ha volume_up
            sleep 0.4
            DB=$(get_volume_db)
            show_overlay "$DB"
        elif echo "$line" | grep -q "KEY_VOLUMEDOWN.*DOWN"; then
            call_ha volume_down
            sleep 0.4
            DB=$(get_volume_db)
            show_overlay "$DB"
        fi
    done

    echo "$(date): Connection lost, reconnecting..."
    sleep 3
    connect_tv
done
