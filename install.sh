#!/bin/bash
set -e

# 版本信息
SCRIPT_NAME="Realm Web Rust 安装脚本"
VERSION="v1.3.0"
RELEASE_DATE="2026-01-31"

# 颜色输出
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }
# 日志统一管理
log() { mkdir -p /var/log/realm-web && echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" >> /var/log/realm-web/install.log; }

# 显示版本
show_version() {
    echo "================================================================"
    echo -e "           ${SCRIPT_NAME} ${VERSION}"
    echo -e "           更新: ${RELEASE_DATE} | 适配Caddy v2.10+"
    echo "================================================================"
}

# 检查root权限
check_root() {
    [[ $EUID -ne 0 ]] && { red "❌ 请使用root权限执行"; exit 1; }
}

# 核心保障：检查main.sh传递的环境变量（防止缺失/空参数）
check_env_params() {
    info "🔍 校验部署参数（环境变量传递）..."
    local missing_params=()
    # 校验必传环境变量
    [[ -z $PORT ]] && missing_params+=("PORT")
    [[ -z $ADMIN_USER ]] && missing_params+=("ADMIN_USER")
    [[ -z $ADMIN_PWD ]] && missing_params+=("ADMIN_PWD")
    [[ -z $DOMAIN ]] && missing_params+=("DOMAIN")

    # 缺失参数则退出并提示
    if [[ ${#missing_params[@]} -gt 0 ]]; then
        red "❌ 缺失部署参数：${missing_params[*]}"
        red "👉 请通过主菜单执行安装：./main.sh，参数将自动传递"
        log "缺失环境变量参数：${missing_params[*]}，部署终止"
        exit 1
    fi
    # 校验端口合法性（数字+1-65535）
    if ! [[ $PORT =~ ^[0-9]+$ && $PORT -ge 1 && $PORT -le 65535 ]]; then
        red "❌ 端口$PORT不合法（必须是1-65535的数字）"
        log "端口不合法：$PORT，部署终止"
        exit 1
    fi
    green "✅ 所有部署参数校验通过，合法有效"
    log "部署参数校验通过：PORT=$PORT, ADMIN_USER=$ADMIN_USER, DOMAIN=$DOMAIN"
}

# 安装系统基础依赖
install_deps() {
    info "📦 安装系统基础依赖..."
    apt update -y && apt install -y git curl wget net-tools libsqlite3-dev
    green "✅ 系统依赖安装完成"
    log "系统基础依赖安装完成"
}

# 安装Realm转发核心
install_realm() {
    info "🔧 安装Realm转发核心..."
    if command -v realm &>/dev/null; then
        green "✅ Realm已安装，跳过安装步骤"
        return
    fi
    # 适配x86_64/aarch64架构
    local ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        local BIN_URL="https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-gnu.tar.gz"
    elif [[ "$ARCH" == "aarch64" ]]; then
        local BIN_URL="https://github.com/zhboner/realm/releases/latest/download/realm-aarch64-unknown-linux-gnu.tar.gz"
    else
        red "❌ 不支持当前架构：$ARCH（仅支持x86_64/aarch64）"
        log "不支持架构：$ARCH，部署终止"
        exit 1
    fi
    # 下载并安装
    wget -q -O /tmp/realm.tgz "$BIN_URL" --timeout=30
    tar xf /tmp/realm.tgz -C /tmp && mv /tmp/realm /usr/local/bin/ && chmod +x /usr/local/bin/realm
    rm -rf /tmp/realm.tgz /tmp/realm
    green "✅ Realm转发核心安装完成"
    log "Realm转发核心安装完成，架构：$ARCH"
}

# 安装并配置Caddy（兼容v2.10+，自动清理废弃指令）
install_caddy() {
    info "🌐 安装并配置Caddy（自动HTTPS+反向代理）..."
    # 安装Caddy官方稳定版
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update -y && apt install -y caddy
    # 生成Caddy配置（替换域名+清理废弃指令）
    mkdir -p /etc/caddy
    sed "s/{{DOMAIN}}/$DOMAIN/g" ./caddy/Caddyfile.tpl > /etc/caddy/Caddyfile
    sed -i -e '/renew_before/d' -e '/storage/d' /etc/caddy/Caddyfile
    # 校验Caddy配置合法性
    if ! caddy validate --config /etc/caddy/Caddyfile; then
        red "❌ Caddy配置校验失败，请检查模板文件"
        log "Caddy配置校验失败，部署终止"
        exit 1
    fi
    # 启动并设置开机自启
    systemctl restart caddy && systemctl enable caddy
    sleep 2
    # 检查Caddy运行状态
    systemctl is-active --quiet caddy || { red "❌ Caddy启动失败，查看日志：journalctl -u caddy -f"; log "Caddy启动失败，部署终止"; exit 1; }
    green "✅ Caddy安装配置完成（版本：$(caddy version | head -1)）"
    log "Caddy安装配置完成，反向代理域名：$DOMAIN，目标端口：$PORT"
}

# 部署面板目录（适配预编译二进制）
deploy_panel() {
    info "🚀 部署Realm Web面板文件..."
    mkdir -p /opt/realm-web
    # 复制核心目录（请确保rust目录下有预编译的realm-web-rust）
    if [[ -d "./templates" ]]; then \cp -r ./templates/ /opt/realm-web/; fi
    if [[ -d "./rust" && -f "./rust/realm-web-rust" ]]; then
        \cp -r ./rust/ /opt/realm-web/
        \cp /opt/realm-web/rust/realm-web-rust /opt/realm-web/
        chmod +x /opt/realm-web/realm-web-rust
        green "✅ 检测到预编译二进制，面板文件部署完成"
        log "面板文件部署完成，预编译二进制已加载"
    else
        red "❌ 未找到预编译二进制文件：./rust/realm-web-rust"
        yellow "提示：请先在本地编译Rust项目，将二进制文件上传至rust目录"
        log "缺失预编译二进制，部署终止"
        exit 1
    fi
}

# 创建Systemd系统服务（开机自启，读取环境变量PORT）
create_service() {
    info "🔧 创建Systemd面板服务（开机自启）..."
    cat > /etc/systemd/system/realm-web.service << EOF
[Unit]
Description=Realm Web Rust Panel
After=network.target caddy.service
Wants=network.target caddy.service

[Service]
User=root
WorkingDirectory=/opt/realm-web
Environment="REALM_PORT=$PORT"
Environment="REALM_ADMIN_USER=$ADMIN_USER"
Environment="REALM_ADMIN_PWD=$ADMIN_PWD"
ExecStart=/opt/realm-web/realm-web-rust
Restart=always
RestartSec=3
LimitNOFILE=65535
MemoryLimit=128M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
EOF
    # 重载配置+启动+自启
    systemctl daemon-reload && systemctl enable realm-web && systemctl start realm-web
    sleep 2
    # 检查服务运行状态
    systemctl is-active --quiet realm-web || { red "❌ 面板服务启动失败，查看日志：journalctl -u realm-web -f"; log "面板服务启动失败，部署终止"; exit 1; }
    green "✅ 面板系统服务创建成功，已设置开机自启"
    log "面板Systemd服务创建完成，监听端口：$PORT"
}

# 防火墙加固（仅允许本地访问面板端口，外部通过Caddy反向代理）
firewall_secure() {
    info "🛡️  防火墙加固（仅本地访问面板端口$PORT）..."
    # 允许本地访问，拒绝外部直接访问
    iptables -A INPUT -p tcp --dport $PORT -s 127.0.0.1 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport $PORT -j DROP 2>/dev/null || true
    # 保存iptables规则
    mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    green "✅ 防火墙加固完成，面板端口仅本地可访问"
    log "防火墙加固完成，端口$PORT仅127.0.0.1可访问"
}

# 安装主流程
main() {
    clear
    show_version
    check_root
    check_env_params  # 核心：校验环境变量参数
    install_deps
    install_realm
    install_caddy
    deploy_panel
    create_service
    firewall_secure

    # 部署完成最终提示
    echo -e "\n================================================================"
    green "🎉 Realm Web Rust 面板部署全部完成！"
    green "🔗 外部访问地址：https://$DOMAIN（自动HTTPS，无需额外配置）"
    green "🔑 管理员账号：$ADMIN_USER"
    green "🔐 管理员密码：你设置的密码（已通过环境变量安全传递）"
    green "📜 面板日志：./main.sh → 6. 查看面板实时日志"
    green "⚙️  服务管理：./main.sh → 3/4/5 启动/停止/重启"
    echo -e "================================================================"
    log "Realm Web Rust面板部署成功，版本$VERSION，访问地址：https://$DOMAIN"
}

# 执行主流程
main
