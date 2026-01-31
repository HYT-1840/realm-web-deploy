#!/bin/bash
set -e

red() { echo -e "\033[31m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }

# 检查root
[[ $EUID -ne 0 ]] && { red "❌ 请使用root权限执行"; exit 1; }

# 实时查看日志
info "📜 正在查看Realm Web面板实时日志（按Ctrl+C退出）..."
journalctl -u realm-web -f --no-pager
