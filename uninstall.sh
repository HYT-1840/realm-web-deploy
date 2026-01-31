#!/bin/bash
set -e

# 颜色输出
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }

# 检查root
check_root() {
    [[ $EUID -ne 0 ]] && { red "❌ 请使用root权限执行"; exit 1; }
}

# 确认卸载
confirm_uninstall() {
    read -p "⚠️  确定卸载Realm Web Rust面板？（保留数据库/转发规则）[y/N] " CONFIRM
    [[ $CONFIRM != "y" && $CONFIRM != "Y" ]] && { yellow "✅ 已取消卸载"; exit 0; }
}

# 核心卸载逻辑
uninstall() {
    # 停止并禁用服务
    systemctl stop realm-web 2>/dev/null || true
    systemctl disable realm-web 2>/dev/null || true
    # 删除面板文件和服务配置
    rm -rf /opt/realm-web
    rm -f /etc/systemd/system/realm-web.service
    rm -f /etc/caddy/Caddyfile
    # 重新加载systemd
    systemctl daemon-reload
    # 日志记录
    mkdir -p /var/log/realm-web && echo "[$(date)] 面板已卸载（保留数据库）" >> /var/log/realm-web/uninstall.log
    green "✅ Realm Web Rust面板卸载完成！"
    yellow "💾 数据库/转发规则已保留，如需彻底删除请手动清理相关文件"
}

# 执行
check_root
confirm_uninstall
uninstall
