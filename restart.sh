#!/bin/bash
set -e

red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }

# 检查root
[[ $EUID -ne 0 ]] && { red "❌ 请使用root权限执行"; exit 1; }

# 重启服务并查看状态
systemctl restart realm-web
systemctl status realm-web --no-pager
green "✅ Realm Web面板服务重启成功"
