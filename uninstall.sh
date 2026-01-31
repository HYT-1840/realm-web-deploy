#!/bin/bash
set -e

# 颜色输出
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }
log() { mkdir -p /var/log/realm-web && echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" >> /var/log/realm-web/uninstall.log; }

# 检查root权限
check_root() {
    [[ $EUID -ne 0 ]] && { red "❌ 请使用root权限执行"; exit 1; }
}

# 校验命令行参数（main.sh传递：keep/delete，默认keep）
check_cli_param() {
    UNINSTALL_MODE=$1
    # 参数默认值：未传递则为keep（兼容直接运行脚本）
    UNINSTALL_MODE=${UNINSTALL_MODE:-keep}
    # 校验参数合法性
    if [[ $UNINSTALL_MODE != "keep" && $UNINSTALL_MODE != "delete" ]]; then
        red "❌ 非法卸载参数：$UNINSTALL_MODE"
        red "👉 仅支持参数：keep（保留数据）/ delete（删除数据）"
        exit 1
    fi
    info "✅ 卸载模式确认：$UNINSTALL_MODE"
    log "卸载模式确认：$UNINSTALL_MODE"
}

# 核心卸载逻辑
uninstall() {
    local UNINSTALL_MODE=$1
    UNINSTALL_MODE=${UNINSTALL_MODE:-keep}

    info "⚠️  开始执行卸载流程，模式：$UNINSTALL_MODE..."
    # 1. 停止并禁用面板服务
    systemctl stop realm-web 2>/dev/null || true
    systemctl disable realm-web 2>/dev/null || true
    # 2. 删除面板文件和系统服务配置
    rm -rf /opt/realm-web
    rm -f /etc/systemd/system/realm-web.service
    # 3. 删除Caddy配置（保留Caddy服务）
    rm -f /etc/caddy/Caddyfile
    # 4. 重载systemd配置
    systemctl daemon-reload 2>/dev/null || true

    # 5. 根据参数判断是否删除数据库/日志
    if [[ $UNINSTALL_MODE == "delete" ]]; then
        rm -rf /var/log/realm-web 2>/dev/null || true
        rm -f /opt/realm-web/realm.db 2>/dev/null || true
        yellow "⚠️  已彻底删除：面板数据库、所有运行日志（数据不可恢复）"
        log "卸载完成（delete模式）：已删除面板程序+数据库+日志"
    else
        green "✅ 已保留：数据库/转发规则（如需恢复可重新部署面板）"
        log "卸载完成（keep模式）：仅删除面板程序，保留数据库/日志"
    fi

    # 6. 保留Realm/Caddy核心（便于重新部署）
    green "✅ 已保留Realm转发核心和Caddy服务，便于后续重新部署"
    echo -e "\n================================================================"
    green "🎉 Realm Web Rust 面板卸载完成！"
    [[ $UNINSTALL_MODE == "keep" ]] && yellow "💾 数据保留提示：如需彻底清理，请手动删除/var/log/realm-web目录"
    echo -e "================================================================"
}

# 主执行逻辑
main() {
    check_root
    check_cli_param $1
    uninstall $1
}

# 执行主逻辑（接收main.sh传递的命令行参数$1）
main $1
