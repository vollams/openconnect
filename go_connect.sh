#!/bin/bash
. /etc/.db-base 2>/dev/null
DB_USER=${USER}
DB_PASS=${PASS}
DB_NAME=${DBNAME}
DB_HOST=${HOST}
SERVER_ID=146
OC_USER=${USERNAME}
VPN_IP=${IP4_LOCAL}
CLIENT_IP=${REMOTE_IP}
LOG=/var/log/ocserv-traffic.log
NOW=$(date '+%Y-%m-%d %H:%M:%S')
echo "$NOW CONNECT user=$OC_USER vpn_ip=$VPN_IP remote=$CLIENT_IP" >> "$LOG"
mysql --ssl-verify-server-cert=OFF -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -h"$DB_HOST" --default-character-set=utf8mb4 2>/dev/null << SQL
INSERT INTO user_connections (username,server_id,protocol,client_ip,bytes_up,bytes_down,status,last_seen)
VALUES ('$OC_USER',$SERVER_ID,'openconnect','$CLIENT_IP',0,0,'connected',NOW())
ON DUPLICATE KEY UPDATE status='connected',client_ip='$CLIENT_IP',last_seen=NOW(),bytes_up=0,bytes_down=0;
INSERT INTO bandwidth_logs (server,server_ip,server_port,since_connected,username,protocol,ipaddress,bytes_received,bytes_sent,bandwidth,time,time_in,time_out,status,timestamp,category)
SELECT '206.81.31.154','206.81.31.154','1194','0','$OC_USER','openconnect','$CLIENT_IP','0','0',0,NOW(),NOW(),'0000-00-00 00:00:00','online',UNIX_TIMESTAMP(),IFNULL((SELECT category FROM users WHERE username='$OC_USER' LIMIT 1),'free');
SQL
exit 0