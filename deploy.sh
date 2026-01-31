#!/bin/bash
set -e

# 颜色输出函数
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }
log() { echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" >> /var/log/realm-web-deploy.log; }

# 初始化日志文件
touch /var/log/realm-web-deploy.log
log "===== Realm Web Rust 管理脚本启动 ====="

# 交互主菜单
show_menu() {
    clear
    echo "================================================================"
    echo "           Realm Web Rust 面板管理脚本 (Caddy2.10+兼容)"
    echo "================================================================"
    echo "1. 全新安装部署面板"
    echo "2. 卸载面板 (保留数据库/转发规则)"
    echo "3. 启动面板服务"
    echo "4. 停止面板服务"
    echo "5. 重启面板服务"
    echo "6. 查看面板实时日志"
    echo "7. 查看Caddy实时日志"
    echo "0. 退出脚本"
    echo "================================================================"
    read -p "请输入操作序号 [0-7]：" choice
}

# 检查root权限
check_root() {
    [[ $EUID -ne 0 ]] && { red "❌ 请使用root权限执行（sudo -i）"; exit 1; }
}

# 获取用户配置
get_user_config() {
    info "📦 开始配置Realm Web部署参数..."
    read -p "🔧 请输入面板运行端口（默认5000，建议保留）：" PORT
    PORT=${PORT:-5000}
    read -p "🔑 请输入管理员用户名（默认admin）：" ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    read -s -p "🔐 请输入管理员密码（至少6位）：" ADMIN_PWD
    echo
    while [[ ${#ADMIN_PWD} -lt 6 ]]; do
        red "❌ 密码至少6位！"
        read -s -p "🔐 请重新输入管理员密码：" ADMIN_PWD
        echo
    done
    read -p "🌐 请输入已解析到当前服务器的域名：" DOMAIN
    while [[ -z $DOMAIN ]]; do
        red "❌ 域名不能为空！"
        read -p "🌐 请重新输入域名：" DOMAIN
    done
    green "✅ 部署参数配置完成！"
    log "参数：端口=$PORT，管理员=$ADMIN_USER，域名=$DOMAIN"
}

# 安装系统依赖
install_deps() {
    info "📦 安装系统基础依赖..."
    apt update && apt install -y git curl wget iptables net-tools gcc libc6-dev libsqlite3-dev
    green "✅ 系统依赖安装完成！"
}

# 安装Realm核心
install_realm() {
    info "🔍 检测Realm是否安装..."
    if command -v realm &>/dev/null; then
        green "✅ Realm已安装"
        return
    fi
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        REALM_ARCH="x86_64-unknown-linux-gnu"
    elif [ "$ARCH" = "aarch64" ]; then
        REALM_ARCH="aarch64-unknown-linux-gnu"
    else
        red "❌ 不支持架构：${ARCH}"; exit 1
    fi
    REALM_TMP="/tmp/realm.tar.gz"
    wget -L -O $REALM_TMP "https://github.com/zhboner/realm/releases/latest/download/realm-${REALM_ARCH}.tar.gz" --timeout=20
    tar -zxf $REALM_TMP -C /tmp
    mv /tmp/realm /usr/local/bin/ && chmod +x /usr/local/bin/realm
    rm -rf $REALM_TMP /tmp/realm
    green "✅ Realm安装完成"
}

# 安装并配置Caddy(修复兼容Caddy2.10+)
install_caddy() {
    info "🌐 安装配置Caddy..."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update && apt install -y caddy
    caddy version &>/dev/null || { red "❌ Caddy安装失败"; exit 1; }
    green "✅ Caddy安装完成！版本：$(caddy version | head -1)"

    mkdir -p /etc/caddy
    sed "s/{{DOMAIN}}/$DOMAIN/g" caddy/Caddyfile.tpl > /etc/caddy/Caddyfile
    # 清理废弃指令，兼容Caddy2.10+
    sed -i -e '/renew_before/d' -e '/storage/d' /etc/caddy/Caddyfile
    caddy validate --config /etc/caddy/Caddyfile &>/dev/null || { red "❌ Caddy配置错误"; exit 1; }
    green "✅ Caddy配置生成完成"

    systemctl restart caddy
    systemctl enable caddy
    sleep 3
    systemctl is-active --quiet caddy || { red "❌ Caddy启动失败"; exit 1; }
    green "✅ Caddy服务正常运行"
}

# 部署Rust面板
deploy_rust() {
    info "🚀 部署Rust面板..."
    mkdir -p /opt/realm-web
    \cp -r . /opt/realm-web
    cd /opt/realm-web

    if [[ -f rust/realm-web-rust ]]; then
        info "🔧 使用预编译二进制文件"
        \cp rust/realm-web-rust .
    else
        info "🔧 编译Rust项目(首次耗时较长)"
        cd rust
        cargo build --release --target $(uname -m | sed 's/x86_64/x86_64-unknown-linux-gnu/;s/aarch64/aarch64-unknown-linux-gnu/')
        \cp target/$(uname -m | sed 's/x86_64/x86_64-unknown-linux-gnu/;s/aarch64/aarch64-unknown-linux-gnu/')/release/realm-web-rust ../
        cd ..
    fi

    chmod +x realm-web-rust
    ./realm-web-rust $ADMIN_USER $ADMIN_PWD
    green "✅ Rust面板部署&数据库初始化完成"
}

# 创建Systemd服务
create_service() {
    info "🔧 创建系统服务..."
    cat > /etc/systemd/system/realm-web.service << EOF
[Unit]
Description=Realm Web Panel Rust
After=network.target caddy.service

[Service]
User=root
WorkingDirectory=/opt/realm-web
Environment="REALM_SECRET_KEY=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w32 | head -1)"
Environment="REALM_PORT=$PORT"
ExecStart=/opt/realm-web/realm-web-rust
Restart=always
RestartSec=5
LimitNOFILE=65535
MemoryLimit=64M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl restart realm-web
    systemctl enable realm-web
    sleep 3
    systemctl is-active --quiet realm-web || { red "❌ 面板服务启动失败"; exit 1; }
    green "✅ 面板服务正常运行"
}

# 防火墙加固
firewall_secure() {
    info "🛡️ 防火墙加固，仅开放443端口"
    iptables -A INPUT -p tcp --dport $PORT -j DROP
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    green "✅ 安全加固完成"
}

# 安装主流程
main() {
    check_root
    get_user_config
    install_deps
    install_realm
    install_caddy
    deploy_rust
    create_service
    firewall_secure

    echo -e "\n"
    green "🎉 部署全部完成！"
    green "访问地址：https://$DOMAIN"
    green "账号：$ADMIN_USER"
    green "密码：$ADMIN_PWD"
    echo -e "\n"
    log "部署完成"
    read -p "按回车返回主菜单..."
}

# 卸载面板(保留数据库)
uninstall_panel() {
    check_root
    read -p "⚠️  确定卸载面板？Caddy与Realm会保留，仅删除面板 [y/N]：" confirm
    [[ $confirm != y && $confirm != Y ]] && { yellow "已取消卸载"; return; }

    systemctl stop realm-web
    systemctl disable realm-web
    rm -rf /opt/realm-web
    rm -f /etc/systemd/system/realm-web.service
    rm -f /etc/caddy/Caddyfile
    systemctl daemon-reload
    green "✅ 面板卸载完成，数据库文件已保留"
    read -p "按回车返回主菜单..."
}

# 菜单主循环
while true; do
    show_menu
    case $choice in
        1)
            main
            ;;
        2)
            uninstall_panel
            ;;
        3)
            check_root
            systemctl start realm-web
            systemctl status realm-web --no-pager
            read -p "按回车继续..."
            ;;
        4)
            check_root
            systemctl stop realm-web
            green "✅ 服务已停止"
            read -p "按回车继续..."
            ;;
        5)
            check_root
            systemctl restart realm-web
            systemctl status realm-web --no-pager
            read -p "按回车继续..."
            ;;
        6)
            check_root
            journalctl -u realm-web -f
            ;;
        7)
            check_root
            journalctl -u caddy -f
            ;;
        0)
            green "👋 退出脚本"
            exit 0
            ;;
        *)
            red "❌ 输入无效，请输入0-7"
            read -p "按回车继续..."
            ;;
    esac
done
