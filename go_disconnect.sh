#!/bin/bash
. /etc/.db-base 2>/dev/null
DB_USER=${USER}
DB_PASS=${PASS}
DB_NAME=${DBNAME}
DB_HOST=${HOST}
SERVER_ID=146
OC_USER=${USERNAME}
BYTES_IN=${STATS_BYTES_IN:-0}
BYTES_OUT=${STATS_BYTES_OUT:-0}
DURATION=${STATS_DURATION:-0}
LOG=/var/log/ocserv-traffic.log
NOW=$(date '+%Y-%m-%d %H:%M:%S')
TOTAL=$((BYTES_IN + BYTES_OUT))
SINCE=$(printf '%02dh:%02dm:%02ds' $((DURATION/3600)) $((DURATION%3600/60)) $((DURATION%60)))
BYTES_IN_HR=$(numfmt --to=iec $BYTES_IN 2>/dev/null || echo "${BYTES_IN}B")
BYTES_OUT_HR=$(numfmt --to=iec $BYTES_OUT 2>/dev/null || echo "${BYTES_OUT}B")
echo "$NOW DISCONNECT user=$OC_USER bytes_in=$BYTES_IN bytes_out=$BYTES_OUT duration=${DURATION}s" >> "$LOG"
mysql --ssl-verify-server-cert=OFF -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -h"$DB_HOST" --default-character-set=utf8mb4 2>/dev/null << SQL
UPDATE user_connections SET status='disconnected',bytes_up=$BYTES_IN,bytes_down=$BYTES_OUT,last_seen=NOW()
WHERE username='$OC_USER' AND server_id=$SERVER_ID AND status='connected' ORDER BY last_seen DESC LIMIT 1;
UPDATE bandwidth_logs SET since_connected='$SINCE',bytes_received='$BYTES_IN_HR',bytes_sent='$BYTES_OUT_HR',bandwidth=$TOTAL,time_out=NOW(),status='offline',timestamp=UNIX_TIMESTAMP()
WHERE username='$OC_USER' AND protocol='openconnect' AND status='online' ORDER BY time_in DESC LIMIT 1;
SQL
exit 0