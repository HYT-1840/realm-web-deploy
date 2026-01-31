#!/bin/bash
set -e

# 颜色输出
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }

# 检查root权限
check_root() {
    [[ $EUID -ne 0 ]] && { red "❌ 请使用root权限执行"; exit 1; }
}

# 重启面板服务
restart_service() {
    info "🔄  正在重启Realm Web面板服务..."
    # 检查服务文件是否存在
    [[ ! -f /etc/systemd/system/realm-web.service ]] && { red "❌ 未找到面板服务配置，请先执行安装：./main.sh → 1"; exit 1; }
    # 重启服务并查看状态
    systemctl restart realm-web
    echo -e "\n📜 面板服务重启后状态："
    systemctl status realm-web --no-pager
    green "✅ Realm Web面板服务重启成功！"
}

# 主执行逻辑
main() {
    check_root
    restart_service
}

# 执行
main
