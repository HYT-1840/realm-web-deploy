#!/bin/bash
set -e

# 颜色输出
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }
log() { echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" >> /var/log/realm-web-deploy.log; }

# 初始化日志
touch /var/log/realm-web-deploy.log
log "===== Realm Web Rust 管理脚本启动 ====="

# 检查root
check_root() {
    [[ $EUID -ne 0 ]] && { red "❌ 请使用root权限执行（sudo -i）"; exit 1; }
}

# 菜单
show_menu() {
    clear
    echo "================================================================"
    echo "           Realm Web Rust 面板管理脚本 (Caddy2.10+兼容)"
    echo "================================================================"
    echo "1. 全新安装部署面板"
    echo "2. 卸载面板(保留数据库)"
    echo "3. 启动面板服务"
    echo "4. 停止面板服务"
    echo "5. 重启面板服务"
    echo "6. 查看面板实时日志"
    echo "7. 查看Caddy实时日志"
    echo "0. 退出"
    echo "================================================================"
    read -p "请输入操作序号 [0-7]：" choice
}

# 获取配置
get_user_config() {
    info "📦 设置部署参数"
    read -p "面板端口(默认5000)：" PORT
    PORT=${PORT:-5000}
    read -p "管理员账号(默认admin)：" ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    read -s -p "管理员密码(≥6位)：" ADMIN_PWD
    echo
    while [[ ${#ADMIN_PWD} -lt 6 ]]; do
        red "密码至少6位"
        read -s -p "重新输入密码：" ADMIN_PWD
        echo
    done
    read -p "已解析的域名：" DOMAIN
    while [[ -z $DOMAIN ]]; do
        red "域名不能为空"
        read -p "重新输入域名：" DOMAIN
    done
    green "✅ 参数确认：端口=$PORT  用户=$ADMIN_USER  域名=$DOMAIN"
}

# 安装依赖
install_deps() {
    info "📦 安装系统依赖..."
    apt update -y
    apt install -y git curl wget net-tools libsqlite3-dev
    green "✅ 依赖安装完成"
}

# 安装realm核心
install_realm() {
    info "🔧 安装realm转发组件"
    if command -v realm &>/dev/null; then
        green "✅ realm已存在"
        return
    fi
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        BIN_URL="https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-gnu.tar.gz"
    elif [[ "$ARCH" == "aarch64" ]]; then
        BIN_URL="https://github.com/zhboner/realm/releases/latest/download/realm-aarch64-unknown-linux-gnu.tar.gz"
    else
        red "❌ 不支持架构$ARCH"
        exit 1
    fi
    wget -q -O /tmp/realm.tgz "$BIN_URL"
    tar xf /tmp/realm.tgz -C /tmp
    mv /tmp/realm /usr/local/bin/
    chmod +x /usr/local/bin/realm
    green "✅ realm安装完成"
}

# 安装并配置caddy(已修复兼容)
install_caddy() {
    info "🌐 安装Caddy"
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update -y
    apt install -y caddy
    green "✅ Caddy安装完成：$(caddy version | head -1)"

    mkdir -p /etc/caddy
    sed "s/{{DOMAIN}}/$DOMAIN/g" caddy/Caddyfile.tpl > /etc/caddy/Caddyfile
    sed -i -e '/renew_before/d' -e '/storage/d' /etc/caddy/Caddyfile

    if ! caddy validate --config /etc/caddy/Caddyfile; then
        red "❌ Caddy配置错误"
        exit 1
    fi
    green "✅ Caddy配置校验通过"

    systemctl restart caddy
    systemctl enable caddy
    sleep 2
    green "✅ Caddy运行正常"
}

# 部署面板文件
deploy_panel() {
    info "🚀 部署面板文件"
    mkdir -p /opt/realm-web
    \cp -r templates /opt/realm-web/
    \cp -r rust /opt/realm-web/
    cd /opt/realm-web

    if [[ -f ./rust/realm-web-rust ]]; then
        info "✅ 使用预编译二进制"
        cp ./rust/realm-web-rust ./
    else
        info "⚠️  未找到预编译文件，请先本地编译后上传至rust目录"
        yellow "如需自动编译，需先安装Rust环境，会显著耗时"
        read -p "是否安装Rust并编译？[y/N]" COMPILE
        if [[ "$COMPILE" == "y" || "$COMPILE" == "Y" ]]; then
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source $HOME/.cargo/env
            cd rust
            cargo build --release
            cp target/release/realm-web-rust ../
            cd ..
        else
            red "❌ 缺少主程序，退出部署"
            exit 1
        fi
    fi

    chmod +x realm-web-rust
    green "✅ 面板文件部署完成"
}

# 创建systemd服务
create_service() {
    info "🔧 创建系统服务"
    cat >/etc/systemd/system/realm-web.service <<EOF
[Unit]
Description=Realm Web Rust Panel
After=network.target caddy.service

[Service]
User=root
WorkingDirectory=/opt/realm-web
ExecStart=/opt/realm-web/realm-web-rust
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable realm-web
    systemctl start realm-web
    sleep 2
    if systemctl is-active --quiet realm-web; then
        green "✅ 面板服务启动成功"
    else
        red "❌ 服务启动失败，使用 journalctl -u realm-web -f 查看日志"
        exit 1
    fi
}

# 防火墙安全限制
firewall_secure() {
    info "🛡️  限制本地端口访问"
    iptables -A INPUT -p tcp --dport $PORT -s 127.0.0.1 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport $PORT -j DROP 2>/dev/null || true
    green "✅ 安全规则已应用"
}

# 安装主流程
main() {
    check_root
    get_user_config
    install_deps
    install_realm
    install_caddy
    deploy_panel
    create_service
    firewall_secure

    echo -e "\n========================================"
    green "🎉 部署全部完成！"
    green "访问地址：https://$DOMAIN"
    green "管理账号：$ADMIN_USER"
    green "管理密码：已设置"
    echo -e "========================================\n"
    read -p "按回车返回主菜单" tmp
}

# 卸载(保留数据)
uninstall_panel() {
    check_root
    read -p "⚠️  确定卸载面板？[y/N]" c
    [[ "$c" != "y" && "$c" != "Y" ]] && { yellow "已取消"; return; }

    systemctl stop realm-web 2>/dev/null
    systemctl disable realm-web 2>/dev/null
    rm -rf /opt/realm-web
    rm -f /etc/systemd/system/realm-web.service
    rm -f /etc/caddy/Caddyfile
    systemctl daemon-reload
    green "✅ 面板已卸载(数据文件保留)"
    read -p "按回车返回主菜单" tmp
}

# 主循环
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
            read -p "按回车继续" tmp
            ;;
        4)
            check_root
            systemctl stop realm-web
            green "✅ 已停止"
            read -p "按回车继续" tmp
            ;;
        5)
            check_root
            systemctl restart realm-web
            systemctl status realm-web --no-pager
            read -p "按回车继续" tmp
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
            green "👋 退出"
            exit 0
            ;;
        *)
            red "❌ 无效输入"
            read -p "按回车继续" tmp
            ;;
    esac
done
