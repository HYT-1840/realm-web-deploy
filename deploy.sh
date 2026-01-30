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
log "===== Realm Web部署脚本启动 ====="

# ===================== 第一步：获取用户配置（新增域名输入）=====================
get_user_config() {
    info "📦 开始配置Realm Web部署参数..."
    # 获取端口
    read -p "🔧 请输入面板运行端口（默认5000，建议保留）：" PORT
    PORT=${PORT:-5000}
    # 获取管理员用户名
    read -p "🔑 请输入管理员用户名（默认admin）：" ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    # 获取管理员密码
    read -p "🔐 请输入管理员密码（至少6位）：" ADMIN_PWD
    while [[ ${#ADMIN_PWD} -lt 6 ]]; do
        red "❌ 密码至少6位！"
        read -p "🔐 请重新输入管理员密码：" ADMIN_PWD
    done
    # 新增：获取域名（核心，Caddy HTTPS需要）
    read -p "🌐 请输入已解析到VPS公网IP的域名（如realm.yourdomain.com）：" DOMAIN
    while [[ -z $DOMAIN ]]; do
        red "❌ 域名不能为空！请先将域名A记录解析到VPS公网IP（159.54.164.223）"
        read -p "🌐 请重新输入已解析的域名：" DOMAIN
    done
    # 验证域名解析（简单校验）
    info "🔍 验证域名解析状态..."
    DOMAIN_IP=$(nslookup $DOMAIN 2>/dev/null | grep -A1 "Address:" | tail -1 | awk '{print $2}')
    if [[ $DOMAIN_IP != "159.54.164.223" ]]; then
        yellow "⚠️  域名解析可能未生效（当前解析IP：$DOMAIN_IP，预期IP：159.54.164.223）"
        yellow "⚠️  请确认域名A记录已解析，否则Caddy无法申请证书！"
        read -p "📌 确认继续部署？（y/n）：" CONFIRM
        [[ $CONFIRM != "y" && $CONFIRM != "Y" ]] && exit 1
    fi
    green "✅ 部署参数配置完成！"
    log "部署参数：端口=$PORT，管理员=$ADMIN_USER，域名=$DOMAIN，VPS公网IP=159.54.164.223"
}

# ===================== 第二步：安装系统依赖 =====================
install_deps() {
    info "📦 安装系统基础依赖..."
    apt update && apt install -y python3 python3-venv python3-pip git curl wget iptables net-tools
    pip3 install --upgrade pip
    green "✅ 系统依赖安装完成！"
    log "系统基础依赖安装完成"
}

# ===================== 第三步：安装Realm（适配新包名，国外VPS专属）=====================
install_realm() {
    info "🔍 检测Realm是否安装..."
    if command -v realm &>/dev/null; then
        green "✅ Realm已安装，版本：$(realm --version 2>/dev/null | head -1 || echo "未知版本")"
        log "Realm已安装，跳过重新安装"
        return
    fi
    log "Realm未安装，执行GitHub官方二进制包安装（适配新包名）"
    
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        REALM_ARCH_FULL="x86_64-unknown-linux-gnu"
    elif [ "$ARCH" = "aarch64" ]; then
        REALM_ARCH_FULL="aarch64-unknown-linux-gnu"
    else
        red "❌ 不支持的架构：${ARCH}"
        log "系统架构${ARCH}不兼容，Realm安装失败"
        exit 1
    fi

    REALM_TMP="/tmp/realm-${REALM_ARCH_FULL}.tar.gz"
    GITHUB_URL="https://github.com/zhboner/realm/releases/latest/download/realm-${REALM_ARCH_FULL}.tar.gz"

    info "🔗 从GitHub下载Realm官方新包..."
    wget --no-check-certificate -L -O ${REALM_TMP} ${GITHUB_URL} --show-progress --timeout=20 --tries=5
    [[ ! -f ${REALM_TMP} || $(du -k ${REALM_TMP} | awk '{print $1}') -lt 10240 ]] && { red "❌ Realm包损坏"; exit 1; }

    rm -rf /tmp/realm-tmp && mkdir -p /tmp/realm-tmp
    tar -zxf ${REALM_TMP} -C /tmp/realm-tmp
    mv /tmp/realm-tmp/realm /usr/local/bin/ && chmod +x /usr/local/bin/realm
    rm -rf /tmp/realm-tmp ${REALM_TMP}

    if command -v realm &>/dev/null; then
        green "✅ Realm安装成功！版本：$(realm --version 2>/dev/null | head -1)"
        log "Realm安装成功，架构：${REALM_ARCH_FULL}"
    else
        red "❌ Realm安装失败"
        exit 1
    fi
}

# ===================== 第四步：新增Caddy安装配置函数（核心整合）=====================
install_caddy() {
    info "🌐 开始安装Caddy（自动HTTPS+反向代理）..."
    # 安装Caddy官方稳定版
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update && apt install -y caddy
    # 验证Caddy安装
    caddy version &>/dev/null || { red "❌ Caddy安装失败"; exit 1; }
    green "✅ Caddy安装完成！版本：$(caddy version | head -1)"
    log "Caddy官方稳定版安装完成"

    # 替换Caddy配置模板中的域名变量，生成正式配置文件
    info "🔧 配置Caddy反向代理（自动替换域名）..."
    mkdir -p /etc/caddy
    sed "s/{{DOMAIN}}/$DOMAIN/g" caddy/Caddyfile.tpl > /etc/caddy/Caddyfile
    # 验证Caddy配置
    caddy validate --config /etc/caddy/Caddyfile &>/dev/null || { red "❌ Caddy配置错误"; exit 1; }
    green "✅ Caddy配置文件生成成功！"
    log "Caddy配置文件生成：/etc/caddy/Caddyfile，域名：$DOMAIN"

    # 启动Caddy并设置开机自启
    systemctl start caddy
    systemctl enable caddy
    sleep 3 # 等待Caddy完成证书申请
    if systemctl is-active --quiet caddy; then
        green "✅ Caddy服务启动成功（已自动申请SSL证书）"
        log "Caddy服务启动成功，开机自启已开启"
    else
        red "❌ Caddy服务启动失败，查看日志：journalctl -u caddy -f"
        exit 1
    fi
}

# ===================== 第五步：部署Realm Web面板（原有逻辑，无修改）=====================
deploy_realm_web() {
    info "🚀 开始部署Realm Web面板..."
    # 创建部署目录
    mkdir -p /opt/realm-web
    cp -r . /opt/realm-web
    cd /opt/realm-web
    # 创建Python虚拟环境
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt --upgrade
    # 初始化数据库
    python app.py $ADMIN_USER $ADMIN_PWD
    # 创建Systemd服务
    cat > /etc/systemd/system/realm-web.service << EOF
[Unit]
Description=Realm Web Panel
After=network.target caddy.service

[Service]
User=root
WorkingDirectory=/opt/realm-web
Environment="REALM_SECRET_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -1)"
Environment="REALM_PORT=$PORT"
ExecStart=/opt/realm-web/venv/bin/gunicorn -w 4 --bind 0.0.0.0:$PORT app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    # 启动面板服务
    systemctl daemon-reload
    systemctl start realm-web
    systemctl enable realm-web
    green "✅ Realm Web面板部署完成！服务已启动并开机自启"
    log "Realm Web面板部署完成，端口：$PORT，管理员：$ADMIN_USER"
}

# ===================== 第六步：安全加固（关闭5000端口公网访问）=====================
security_harden() {
    info "🛡️  开始安全加固（关闭$PORT端口公网访问，仅保留HTTPS 443端口）..."
    # 关闭指定端口的公网入站访问
    iptables -A INPUT -p tcp --dport $PORT -j DROP
    # 保存iptables规则（Ubuntu/Debian）
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    green "✅ 安全加固完成！$PORT端口公网访问已关闭，仅可通过HTTPS访问"
    log "安全加固：关闭$PORT端口公网访问，保存iptables规则"
}

# ===================== 主执行流程 =====================
main() {
    # 检查是否为root权限
    [[ $EUID -ne 0 ]] && { red "❌ 请使用root权限执行（sudo -i）"; exit 1; }
    # 执行所有步骤
    get_user_config
    install_deps
    install_realm
    install_caddy # 新增Caddy执行步骤
    deploy_realm_web
    security_harden
    # 部署完成提示
    echo -e "\n"
    green "🎉 Realm Web面板+HTTPS代理 部署完成！"
    green "📢 安全访问地址：https://$DOMAIN"
    green "🔑 管理员账号：$ADMIN_USER"
    green "🔐 管理员密码：$ADMIN_PWD"
    green "⚠️  请立即登录并修改管理员密码，切勿泄露！"
    echo -e "\n"
    log "===== Realm Web部署全流程完成 ====="
}

# 执行主函数
main
