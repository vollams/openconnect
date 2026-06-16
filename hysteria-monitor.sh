#!/bin/bash
###############################################################################
# Hysteria 2 - Bandwidth Monitor
# Parses systemd journal for client disconnect events (tx/rx bytes),
# reports each session to report.php (which accumulates bandwidth,
# enforces limits, and sets bw_exceeded), and updates bandwidth_logs.
#
# Cron (every 5 min):  */5 * * * * /root/hysteria-monitor.sh
# Also called by agent.sh every 30s.
###############################################################################

. /root/.db-base        2>/dev/null
. /root/.panel_config   2>/dev/null   # PANEL_URL + API_KEY

LOG=/var/log/hysteria-traffic.log
LAST_TS_FILE=/var/run/hysteria-monitor-lastts

[ -z "$PANEL_URL" ] && PANEL_URL="${PANEL_URL:-}"
[ -z "$API_KEY" ]   && API_KEY="${API_KEY:-}"

# Resume from last processed timestamp to avoid duplicates
LAST_TS=$(cat "$LAST_TS_FILE" 2>/dev/null || echo "2000-01-01")

# Hysteria 2 disconnect log format:
# "client disconnected" {"addr":"1.2.3.4:port","auth":"username","tx":12345,"rx":67890}
journalctl -u hysteria-server --since="$LAST_TS" --no-pager -o short-iso 2>/dev/null \
| grep "client disconnected" \
| while read -r line; do
    AUTH=$(echo "$line" | grep -oP '"auth"\s*:\s*"\K[^"]+')
    ADDR=$(echo "$line" | grep -oP '"addr"\s*:\s*"\K[^"]+')
    TX=$(echo "$line"   | grep -oP '"tx"\s*:\s*\K[0-9]+')
    RX=$(echo "$line"   | grep -oP '"rx"\s*:\s*\K[0-9]+')

    [ -z "$TX" ] && TX=0
    [ -z "$RX" ] && RX=0
    TOTAL=$((TX + RX))
    # Extract client IP (strip port)
    CLIENT_IP=$(echo "$ADDR" | cut -d: -f1)
    HY_USER="${AUTH:-anonymous}"

    echo "$(date '+%Y-%m-%d %H:%M:%S') DISCONNECT user=$HY_USER addr=$ADDR tx=$TX rx=$RX" >> "$LOG"

    # ── Report to report.php (accumulates to users table + enforces limits) ──
    if [ -n "$PANEL_URL" ] && [ -n "$API_KEY" ]; then
        curl -4 -sf --max-time 20 \
            -X POST "${PANEL_URL}/api/usage/report.php" \
            -H "Authorization: Bearer ${API_KEY}" \
            -H "Content-Type: application/json" \
            -d "{\"connections\":[{\"username\":\"$HY_USER\",\"protocol\":\"hysteria\",\"bytes_up\":$TX,\"bytes_down\":$RX,\"client_ip\":\"$CLIENT_IP\",\"status\":\"disconnected\"}]}" \
            >/dev/null 2>&1
    fi

    # ── Direct DB update: user_connections + bandwidth_logs + users ──────────
    mysql --ssl-verify-server-cert=OFF \
        -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -h"$DB_HOST" \
        --default-character-set=utf8mb4 2>/dev/null << SQL
UPDATE user_connections
SET status='disconnected', bytes_up=$TX, bytes_down=$RX, last_seen=NOW()
WHERE username='$HY_USER' AND protocol='hysteria' AND status='connected'
ORDER BY last_seen DESC LIMIT 1;

UPDATE bandwidth_logs
SET bytes_received=$RX, bytes_sent=$TX, bandwidth=$TOTAL,
    time_out=NOW(), status='offline', timestamp=UNIX_TIMESTAMP()
WHERE username='$HY_USER' AND protocol='hysteria' AND status='online'
ORDER BY time_in DESC LIMIT 1;

UPDATE users SET
    bytes_sent     = bytes_sent     + $TX,
    bytes_received = bytes_received + $RX,
    bandwidth      = bandwidth      + $TOTAL
WHERE user_name = '$HY_USER' LIMIT 1;

UPDATE users SET is_active=0, bw_exceeded=1
WHERE user_name = '$HY_USER'
  AND COALESCE(bandwidth_limit, 0) > 0
  AND (bytes_sent + bytes_received) >= bandwidth_limit
LIMIT 1;
SQL
done

# Save current timestamp for next run
date --iso-8601=seconds > "$LAST_TS_FILE"