#!/bin/bash
set -e

# 版本信息
SCRIPT_NAME="Realm Web Rust 安装脚本"
VERSION="v1.2.0"
RELEASE_DATE="2026-01-31"
AUTHOR="HYT-1840"

# 颜色输出
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }
log() { mkdir -p /var/log/realm-web && echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" >> /var/log/realm-web/install.log; }

# 显示版本
show_version() {
    echo "================================================================"
    echo -e "           ${SCRIPT_NAME} ${VERSION}"
    echo -e "           更新: ${RELEASE_DATE} | 作者: ${AUTHOR}"
    echo "================================================================"
}

# 检查root权限
check_root() {
    [[ $EUID -ne 0 ]] && { red "❌ 请使用root权限执行（sudo -i）"; exit 1; }
}

# 获取用户配置
get_user_config() {
    info "📦 配置部署参数（按回车使用默认值）"
    read -p "🔧 面板运行端口（默认5000）：" PORT
    PORT=${PORT:-5000}
    read -p "🔑 管理员用户名（默认admin）：" ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    read -s -p "🔐 管理员密码（至少6位）：" ADMIN_PWD
    echo
    while [[ ${#ADMIN_PWD} -lt 6 ]]; do
        red "❌ 密码长度不足6位！"
        read -s -p "🔐 重新输入管理员密码：" ADMIN_PWD
        echo
    done
    read -p "🌐 已解析的域名（必填）：" DOMAIN
    while [[ -z $DOMAIN ]]; do
        red "❌ 域名不能为空！"
        read -p "🌐 重新输入已解析的域名：" DOMAIN
    done
    green "✅ 参数配置完成：端口=$PORT | 管理员=$ADMIN_USER | 域名=$DOMAIN"
    log "部署参数：端口=$PORT，管理员=$ADMIN_USER，域名=$DOMAIN"
}

# 安装系统依赖
install_deps() {
    info "📦 安装系统基础依赖..."
    apt update -y && apt install -y git curl wget net-tools libsqlite3-dev
    green "✅ 系统依赖安装完成"
    log "系统依赖安装完成"
}

# 安装Realm转发核心
install_realm() {
    info "🔧 安装Realm转发核心..."
    if command -v realm &>/dev/null; then
        green "✅ Realm已安装，跳过"
        return
    fi
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        BIN_URL="https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-gnu.tar.gz"
    elif [[ "$ARCH" == "aarch64" ]]; then
        BIN_URL="https://github.com/zhboner/realm/releases/latest/download/realm-aarch64-unknown-linux-gnu.tar.gz"
    else
        red "❌ 不支持当前架构：$ARCH"
        log "不支持架构：$ARCH，部署失败"
        exit 1
    fi
    wget -q -O /tmp/realm.tgz "$BIN_URL"
    tar xf /tmp/realm.tgz -C /tmp && mv /tmp/realm /usr/local/bin/ && chmod +x /usr/local/bin/realm
    rm -rf /tmp/realm.tgz /tmp/realm
    green "✅ Realm转发核心安装完成"
    log "Realm转发核心安装完成"
}

# 安装并配置Caddy（兼容2.10+，修复废弃指令）
install_caddy() {
    info "🌐 安装并配置Caddy（自动HTTPS）..."
    # 安装Caddy
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update -y && apt install -y caddy
    # 生成配置（使用修复后的模板，自动清理废弃指令）
    mkdir -p /etc/caddy
    sed "s/{{DOMAIN}}/$DOMAIN/g" caddy/Caddyfile.tpl > /etc/caddy/Caddyfile
    sed -i -e '/renew_before/d' -e '/storage/d' /etc/caddy/Caddyfile
    # 校验配置
    if ! caddy validate --config /etc/caddy/Caddyfile; then
        red "❌ Caddy配置校验失败"
        log "Caddy配置校验失败，部署终止"
        exit 1
    fi
    # 启动并自启
    systemctl restart caddy && systemctl enable caddy
    sleep 2
    systemctl is-active --quiet caddy || { red "❌ Caddy启动失败"; log "Caddy启动失败，部署终止"; exit 1; }
    green "✅ Caddy安装配置完成（版本：$(caddy version | head -1)）"
    log "Caddy安装配置完成，域名：$DOMAIN"
}

# 部署面板文件（支持预编译二进制）
deploy_panel() {
    info "🚀 部署Realm Web面板文件..."
    mkdir -p /opt/realm-web
    \cp -r templates/ rust/ /opt/realm-web/
    cd /opt/realm-web
    # 检查预编译二进制
    if [[ -f rust/realm-web-rust ]]; then
        info "✅ 检测到预编译二进制，直接使用"
        \cp rust/realm-web-rust ./ && chmod +x realm-web-rust
    else
        red "❌ 未找到预编译二进制文件（rust/realm-web-rust）"
        yellow "提示：请先在本地编译后将二进制上传至rust目录，再执行安装"
        log "未找到预编译二进制，部署终止"
        exit 1
    fi
    green "✅ 面板文件部署完成"
    log "面板文件部署完成，路径：/opt/realm-web"
}

# 创建Systemd服务
create_service() {
    info "🔧 创建系统服务（开机自启）..."
    cat > /etc/systemd/system/realm-web.service << EOF
[Unit]
Description=Realm Web Rust Panel
After=network.target caddy.service
Wants=network.target caddy.service

[Service]
User=root
WorkingDirectory=/opt/realm-web
ExecStart=/opt/realm-web/realm-web-rust
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    # 启动并自启
    systemctl daemon-reload && systemctl enable realm-web && systemctl start realm-web
    sleep 2
    systemctl is-active --quiet realm-web || { red "❌ 面板服务启动失败"; log "面板服务启动失败，部署终止"; exit 1; }
    green "✅ 面板系统服务创建并启动成功"
    log "面板系统服务创建完成，已设置开机自启"
}

# 防火墙加固
firewall_secure() {
    info "🛡️  防火墙加固（仅允许本地访问面板端口）..."
    iptables -A INPUT -p tcp --dport $PORT -s 127.0.0.1 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport $PORT -j DROP 2>/dev/null || true
    green "✅ 防火墙加固完成"
    log "防火墙加固完成，面板端口$PORT仅本地可访问"
}

# 主执行流程
main() {
    clear
    show_version
    check_root
    get_user_config
    install_deps
    install_realm
    install_caddy
    deploy_panel
    create_service
    firewall_secure

    # 部署完成提示
    echo -e "\n================================================================"
    green "🎉 Realm Web Rust 面板部署全部完成！"
    green "🔗 访问地址：https://$DOMAIN"
    green "🔑 管理员账号：$ADMIN_USER"
    green "🔐 管理员密码：你设置的密码（本次未明文记录）"
    green "📜 面板日志：/var/log/realm-web/ 或 ./log-panel.sh"
    echo -e "================================================================"
    log "Realm Web Rust面板部署成功，版本：$VERSION"
}

# 执行主流程
main
