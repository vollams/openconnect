#!/bin/bash
. /etc/.db-base 2>/dev/null

# ── Read dynamic config (supports multiple panels) ──
SERVER_ID=0
if [ -f /etc/vollam/panel.conf ]; then
    . /etc/vollam/panel.conf
fi
# Fallback: try to get SERVER_ID from panel API or db-base
if [ "$SERVER_ID" = "0" ] && [ -n "$PANEL_URL" ] && [ -n "$API_KEY" ]; then
    _MY_IP=$(curl -s https://api.ipify.org 2>/dev/null)
    if [ -n "$_MY_IP" ]; then
        _SID=$(curl -s "$PANEL_URL/api/v1/endpoints/auto_register.php?ip=$_MY_IP" 2>/dev/null | grep -oP '(?<="server_id":)\d+' | head -1)
        [ -n "$_SID" ] && SERVER_ID=$_SID
    fi
fi

DB_USER=${USER}
DB_PASS=${PASS}
DB_NAME=${DBNAME}
DB_HOST=${HOST}
OC_USER=${USERNAME}
VPN_IP=${IP4_LOCAL}
CLIENT_IP=${REMOTE_IP}
MY_SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "127.0.0.1")
LOG=/var/log/ocserv-traffic.log
NOW=$(date '+%Y-%m-%d %H:%M:%S')
echo "$NOW CONNECT user=$OC_USER vpn_ip=$VPN_IP remote=$CLIENT_IP" >> "$LOG"
mysql --ssl-verify-server-cert=OFF -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -h"$DB_HOST" --default-character-set=utf8mb4 2>/dev/null << SQL
INSERT INTO user_connections (username,server_id,protocol,client_ip,bytes_up,bytes_down,status,last_seen)
VALUES ('$OC_USER',$SERVER_ID,'openconnect','$CLIENT_IP',0,0,'connected',NOW())
ON DUPLICATE KEY UPDATE status='connected',client_ip='$CLIENT_IP',last_seen=NOW(),bytes_up=0,bytes_down=0;
INSERT INTO bandwidth_logs (server,server_ip,server_port,since_connected,username,protocol,ipaddress,bytes_received,bytes_sent,bandwidth,time,time_in,time_out,status,timestamp,category)
SELECT '$MY_SERVER_IP','$MY_SERVER_IP','1194','0','$OC_USER','openconnect','$CLIENT_IP','0','0',0,NOW(),NOW(),'0000-00-00 00:00:00','online',UNIX_TIMESTAMP(),IFNULL((SELECT category FROM users WHERE username='$OC_USER' LIMIT 1),'free');
SQL
exit 0