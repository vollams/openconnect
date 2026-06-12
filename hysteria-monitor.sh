#!/bin/bash
# Hysteria 2 bandwidth monitor - parses journal logs for session stats

# ── Configuration: read from panel.conf (supports multiple panels) ──
PANEL_URL=""
API_KEY=""
if [ -f /etc/vollam/panel.conf ]; then
    . /etc/vollam/panel.conf
elif [ -f /etc/.db-base ]; then
    . /etc/.db-base
elif [ -f /root/.db-base ]; then
    . /root/.db-base
fi

LOG=/var/log/hysteria-traffic.log
LAST_TS_FILE=/var/run/hysteria-monitor-lastts

# Skip if no panel config
[ -z "$PANEL_URL" ] || [ -z "$API_KEY" ] && exit 0

# Get last processed timestamp
LAST_TS=$(cat "$LAST_TS_FILE" 2>/dev/null || echo "2000-01-01")

# Parse Hysteria disconnect events: "client disconnected" with tx/rx bytes
journalctl -u hysteria-server --since="$LAST_TS" --no-pager -o short-iso 2>/dev/null | \
grep "client disconnected" | while read -r line; do
    TIMESTAMP=$(echo "$line" | grep -oP '^\S+')
    AUTH=$(echo "$line" | grep -oP '"auth"\s*:\s*"\K[^"]+')
    ADDR=$(echo "$line" | grep -oP '"addr"\s*:\s*"\K[^"]+')
    TX=$(echo "$line" | grep -oP '"tx"\s*:\s*\K[0-9]+')
    RX=$(echo "$line" | grep -oP '"rx"\s*:\s*\K[0-9]+')

    [ -z "$TX" ] && TX=0
    [ -z "$RX" ] && RX=0

    echo "$(date '+%Y-%m-%d %H:%M:%S') DISCONNECT user=${AUTH:-anonymous} addr=$ADDR tx=$TX rx=$RX" >> "$LOG"

    curl -4 -sf -X POST "${PANEL_URL}/api/v1/endpoints/server.php" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "{\"action\":\"report_bandwidth\",\"protocol\":\"hysteria\",\"user\":\"${AUTH:-anonymous}\",\"bytes_in\":${RX},\"bytes_out\":${TX}}" \
        >/dev/null 2>&1
done

# Save current timestamp
date --iso-8601=seconds > "$LAST_TS_FILE"
