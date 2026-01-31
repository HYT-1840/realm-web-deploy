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

# 停止面板服务
stop_service() {
    info "⏹️  正在停止Realm Web面板服务..."
    systemctl stop realm-web 2>/dev/null || true
    green "✅ Realm Web面板服务已成功停止！"
}

# 主执行逻辑
main() {
    check_root
    stop_service
}

# 执行
main
