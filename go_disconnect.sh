#!/bin/bash
###############################################################################
# OpenConnect (ocserv) - User Disconnect Script
# Called by ocserv on every session end (logout, timeout, or drop).
# Environment variables provided by ocserv:
#   USERNAME         - authenticated username
#   STATS_BYTES_IN   - bytes received by server from client (client upload)
#   STATS_BYTES_OUT  - bytes sent by server to client (client download)
#   STATS_DURATION   - session duration in seconds
#
# SETUP: Replace __SERVER_ID__ before deploying.
###############################################################################

. /etc/.db-base 2>/dev/null

SERVER_ID=__SERVER_ID__

OC_USER=${USERNAME}
BYTES_IN=${STATS_BYTES_IN:-0}
BYTES_OUT=${STATS_BYTES_OUT:-0}
DURATION=${STATS_DURATION:-0}
LOG=/var/log/ocserv-traffic.log

TOTAL=$((BYTES_IN + BYTES_OUT))
SINCE=$(printf '%02dh:%02dm:%02ds' $((DURATION/3600)) $((DURATION%3600/60)) $((DURATION%60)))

echo "$(date '+%Y-%m-%d %H:%M:%S') DISCONNECT user=$OC_USER bytes_in=$BYTES_IN bytes_out=$BYTES_OUT duration=${DURATION}s" >> "$LOG"

mysql --ssl-verify-server-cert=OFF \
    -u"$USER" -p"$PASS" -D"$DBNAME" -h"$HOST" \
    --default-character-set=utf8mb4 2>/dev/null << SQL
UPDATE user_connections
SET status='disconnected', bytes_up=$BYTES_IN, bytes_down=$BYTES_OUT, last_seen=NOW()
WHERE username='$OC_USER' AND server_id=$SERVER_ID AND status='connected'
ORDER BY last_seen DESC LIMIT 1;

UPDATE bandwidth_logs
SET since_connected='$SINCE',
    bytes_received=$BYTES_IN,
    bytes_sent=$BYTES_OUT,
    bandwidth=$TOTAL,
    time_out=NOW(),
    status='offline',
    timestamp=UNIX_TIMESTAMP()
WHERE username='$OC_USER' AND protocol='openconnect' AND status='online'
ORDER BY time_in DESC LIMIT 1;

UPDATE users SET
    bytes_sent     = bytes_sent     + $BYTES_IN,
    bytes_received = bytes_received + $BYTES_OUT,
    bandwidth      = bandwidth      + $TOTAL
WHERE user_name = '$OC_USER' LIMIT 1;

UPDATE users SET is_active=0, bw_exceeded=1
WHERE user_name = '$OC_USER'
  AND COALESCE(bandwidth_limit, 0) > 0
  AND (bytes_sent + bytes_received) >= bandwidth_limit
LIMIT 1;
SQL

exit 0