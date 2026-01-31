#!/bin/bash
set -e

# 颜色输出
red() { echo -e "\033[31m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }

# 检查root权限
check_root() {
    [[ $EUID -ne 0 ]] && { red "❌ 请使用root权限执行"; exit 1; }
}

# 校验日志行数参数
check_log_param() {
    LOG_LINES=$1
    LOG_LINES=${LOG_LINES:-0}
    if ! [[ $LOG_LINES =~ ^[0-9]+$ ]]; then
        red "❌ 非法日志行数：$LOG_LINES（必须是非负整数）"
        exit 1
    fi
    info "✅ 日志查看配置：$( [[ $LOG_LINES -eq 0 ]] && echo "实时滚动模式" || echo "最后$LOG_LINES行+实时滚动模式" )"
}

# 查看Caddy实时日志
view_log() {
    LOG_LINES=$1
    LOG_LINES=${LOG_LINES:-0}

    info "📜 正在查看Caddy反向代理实时日志（按Ctrl+C退出查看）..."
    # 检查Caddy是否安装
    command -v caddy &>/dev/null || { red "❌ Caddy未安装，请先执行面板安装：./main.sh → 1"; exit 1; }
    # 根据参数执行日志命令
    if [[ $LOG_LINES -eq 0 ]]; then
        journalctl -u caddy -f --no-pager
    else
        journalctl -u caddy -n $LOG_LINES -f --no-pager
    fi
}

# 主执行逻辑
main() {
    check_root
    check_log_param $1
    view_log $1
}

# 执行（接收main.sh传递的命令行参数$1）
main $1
