#!/bin/bash

# 全局变量
LOG_FILE="/var/log/network.log"
INTF="eth0"   
BACKUP_FILE="/etc/network/interfaces.bak"
SCRIPT_PATH=$(readlink -f "$0") # 获取当前脚本的绝对路径

# 生产网参数
STATIC_IP="172.22.146.150"
NETMASK="255.255.255.0"
GATEWAY="172.22.146.1"
DNS1="172.22.146.53"
DNS2="172.22.146.54"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" | sudo tee -a "$LOG_FILE"
}

# 自动管理 Crontab 
update_cron() {
    local action=$1
    # 1. 导出当前 crontab，并过滤掉包含本脚本的旧条目
    sudo crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" > /tmp/cron.tmp
    
    if [ "$action" == "add" ]; then
        # 2. 追加新条目 
        echo "* * * * * $SCRIPT_PATH check" >> /tmp/cron.tmp
        log "INFO" "已添加自动检测定时任务"
    else
        log "INFO" "已移除自动检测定时任务"
    fi
    # 3. 重新导入 crontab
    sudo crontab /tmp/cron.tmp
    rm -f /tmp/cron.tmp
}

apply_network() {
    local mode=$1
    # 首次运行自动备份 
    if [ ! -f "$BACKUP_FILE" ]; then
        sudo cp /etc/network/interfaces "$BACKUP_FILE"
        log "INFO" "原始配置已备份至 $BACKUP_FILE"
    fi
    if [ "$mode" == "dhcp" ]; then
        log "INFO" ">>> 切换操作：办公网络模式 (DHCP)"
        # 写入配置 
        echo -e "auto lo\niface lo inet loopback\n\nauto $INTF\niface $INTF inet dhcp" | sudo tee /etc/network/interfaces > /dev/null
        # 清理防火墙，移除定时任务
        sudo iptables -P OUTPUT ACCEPT
        sudo iptables -F
        update_cron "remove"
    else
        log "INFO" ">>> 切换操作：生产网络模式 (Static)"
        # 写入配置
        echo -e "auto lo\niface lo inet loopback\n\nauto $INTF\niface $INTF inet static\n    address $STATIC_IP\n    netmask $NETMASK\n    gateway $GATEWAY" | sudo tee /etc/network/interfaces > /dev/null
        echo -e "nameserver $DNS1\nnameserver $DNS2" | sudo tee /etc/resolv.conf > /dev/null
        # 应用防火墙，添加定时任务
        sudo iptables -F
        sudo iptables -A OUTPUT -o lo -j ACCEPT
        sudo iptables -A OUTPUT -d 172.22.146.0/24 -j ACCEPT
        sudo iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
        sudo iptables -P OUTPUT DROP
        # 自动添加监控任务
        update_cron "add"
    fi
    # 重启网络
    sudo systemctl restart networking
    sudo ifdown $INTF 2>/dev/null && sudo ifup $INTF 2>/dev/null
    log "SUCCESS" "网络配置已更新为 $mode 模式"
}

check_and_switch() {
    if ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
        log "CRITICAL" " 违规警告：生产环境检测到公网连通，正在强制回滚"
        apply_network "dhcp"
    fi
}

# 回滚操作
rollback() {
    log "INFO" ">>> 执行系统回滚"
    if [ -f "$BACKUP_FILE" ]; then
        sudo cp "$BACKUP_FILE" /etc/network/interfaces
        log "INFO" "已恢复原始网络配置文件"
    fi
    sudo iptables -P OUTPUT ACCEPT
    sudo iptables -F
    update_cron "remove"
    sudo systemctl restart networking
    sudo ifdown $INTF 2>/dev/null && sudo ifup $INTF 2>/dev/null
    log "SUCCESS" "系统已回滚至初始状态"
}

# 主菜单
case "$1" in
    dhcp)   apply_network "dhcp" ;;
    static) apply_network "static" ;;
    check)  check_and_switch ;;
    rollback) rollback ;;

    *)

        echo "用法: $0 {dhcp|static|check|rollback}"
        echo "  dhcp    : 办公模式 "
        echo "  static  : 生产模式 "
        echo "  check   : 仅供 Crontab 调用的检测接口"
        echo "  rollback: 恢复实验前状态"
        exit 1
        ;;

esac
