#!/bin/bash
###############################################################################
# VPN Panel Agent - Task Executor
###############################################################################

PANEL_URL="https://v2raynet.xyz"
API_KEY="srv_f9844e56a0594e16914c397090da9ce753f3c7388965d35977189d60f1200570"
POLL_INTERVAL=10
LOG_FILE="/var/log/vpn-panel-agent.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_service() {
    systemctl is-active "$1" 2>/dev/null | grep -q "^active$" && echo "active" || echo "inactive"
}

count_oc_online() {
    local n
    n=$(occtl show users 2>/dev/null | grep -c "^Username:") 2>/dev/null
    echo "${n:-0}"
}

count_hysteria_online() {
    local n
    n=$(journalctl -u hysteria-server --since="1 minute ago" --no-pager 2>/dev/null | grep -c "client connected") 2>/dev/null
    echo "${n:-0}"
}

send_heartbeat() {
    local cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "0")
    local mem=$(free | grep Mem | awk '{printf("%.2f", $3/$2 * 100.0)}' 2>/dev/null || echo "0")
    local disk=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || echo "0")

    local hysteria_st=$(check_service hysteria-server.service)
    local ocserv_st=$(check_service ocserv.service)
    local openvpn_tcp=$(check_service openvpn@server2.service)
    local openvpn_udp=$(check_service openvpn@server.service)
    local stunnel_st=$(check_service stunnel4.service)
    local squid_st=$(check_service squid.service)
    [ "$squid_st" = "inactive" ] && squid_st=$(check_service squid3.service)
    local ssh_st=$(check_service ssh.service)
    local dropbear_st=$(check_service dropbear.service)
    local xray_st=$(check_service xray.service)
    local xray_domain=$(cat /etc/xray/.domain 2>/dev/null | head -1 | tr -d '\n' || echo "")
    local xray_tls_port=$(grep xray_tls_port /root/.ports 2>/dev/null | cut -d= -f2 || echo "443")
    local xray_ntls_port=$(grep xray_ntls_port /root/.ports 2>/dev/null | cut -d= -f2 || echo "80")

    local ovpn_online=0
    if [ -f /var/log/openvpn/status.log ]; then
        ovpn_online=$(grep -c "^CLIENT_LIST" /var/log/openvpn/status.log 2>/dev/null || echo "0")
    fi
    local oc_online=$(count_oc_online)
    local hy_online=$(count_hysteria_online)
    local total_online=$((ovpn_online + oc_online + hy_online))

    local os_info=$(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Unknown")
    local mem_info="$(free -m | awk 'NR==2{print $3}')MB / $(free -m | awk 'NR==2{print $2}')MB"
    local disk_info=$(df -h / | awk 'NR==2{print $3" / "$2}' 2>/dev/null || echo "Unknown")
    local uptime_info=$(uptime -p 2>/dev/null || echo "Unknown")
    local cpu_model=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "Unknown")
    local bandwidth=$(vnstat --oneline 2>/dev/null | cut -d';' -f11 || echo "N/A")

    local hysteria_port=$(grep hysteria_port /root/.ports 2>/dev/null | cut -d= -f2 || echo "5666")
    local ssh_port=$(grep ssh_port /root/.ports 2>/dev/null | cut -d= -f2 || echo "22")
    local dropbear_port=$(grep dropbear_port /root/.ports 2>/dev/null | cut -d= -f2 || echo "0")
    local tcp_port=$(grep tcp_port /root/.ports 2>/dev/null | cut -d= -f2 || echo "1194")
    local ocserv_port=$(grep tcp_port /root/.ports 2>/dev/null | cut -d= -f2 || echo "1194")

    curl -4 -s -X POST "${PANEL_URL}/api/v1/endpoints/server.php" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "{\"action\":\"heartbeat\",\"cpu\":\"$cpu\",\"memory\":\"$mem\",\"disk\":\"$disk\",\"services\":{\"hysteria\":\"$hysteria_st\",\"ocserv\":\"$ocserv_st\",\"openvpn_tcp\":\"$openvpn_tcp\",\"openvpn_udp\":\"$openvpn_udp\",\"stunnel\":\"$stunnel_st\",\"squid\":\"$squid_st\",\"ssh\":\"$ssh_st\",\"dropbear\":\"$dropbear_st\",\"xray\":\"$xray_st\"},\"info\":{\"os\":\"$os_info\",\"memory\":\"$mem_info\",\"disk\":\"$disk_info\",\"uptime\":\"$uptime_info\",\"cpu_model\":\"$cpu_model\",\"bandwidth\":\"$bandwidth\",\"online\":$total_online,\"ovpn_online\":$ovpn_online,\"oc_online\":$oc_online,\"hysteria_online\":$hy_online,\"hysteria_port\":\"$hysteria_port\",\"ocserv_port\":\"$ocserv_port\",\"ssh_port\":\"$ssh_port\",\"dropbear_port\":\"$dropbear_port\",\"xray_domain\":\"$xray_domain\",\"xray_tls_port\":\"$xray_tls_port\",\"xray_ntls_port\":\"$xray_ntls_port\"}}" \
        >/dev/null 2>&1
}

poll_tasks() {
    local response=$(curl -4 -s -X POST "${PANEL_URL}/api/v1/endpoints/server.php" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d '{"action":"poll_tasks"}' 2>/dev/null)
    printf '%s\n' "$response"
}

execute_task() {
    local task_id=$1
    local command=$2
    log "Executing task #$task_id"
    output=$(eval "$command" 2>&1)
    exit_code=$?
    local status="completed"
    if [ $exit_code -ne 0 ]; then
        status="failed"
        log "Task #$task_id failed with exit code $exit_code"
    else
        log "Task #$task_id completed successfully"
    fi
    curl -4 -s -X POST "${PANEL_URL}/api/v1/endpoints/server.php" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "{\"action\":\"report_task\",\"task_id\":$task_id,\"status\":\"$status\",\"output\":\"$(echo "$output" | head -c 500)\"}" \
        >/dev/null 2>&1
}

log "Agent started - Panel: $PANEL_URL"

while true; do
    if [ $((SECONDS % 30)) -eq 0 ]; then
        send_heartbeat
        /root/hysteria-monitor.sh >/dev/null 2>&1 &
    fi

    tasks=$(poll_tasks)

    if printf '%s\n' "$tasks" | grep -q "task_id"; then
        log "Tasks received, processing..."
        printf '%s\n' "$tasks" | jq -c '.tasks[]' 2>/dev/null | while IFS= read -r task; do
            task_id=$(printf '%s\n' "$task" | jq -r '.task_id' 2>/dev/null)
            command=$(printf '%s\n' "$task" | jq -r '.command' 2>/dev/null)
            if [ ! -z "$task_id" ] && [ "$task_id" != "null" ]; then
                execute_task "$task_id" "$command" &
            fi
        done
    fi

    sleep $POLL_INTERVAL
done

