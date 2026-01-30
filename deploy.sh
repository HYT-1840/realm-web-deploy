#!/bin/bash
set -euo pipefail

# ===================== 基础配置（可修改）=====================
DEPLOY_DIR="/opt/realm-web"          # 部署目录
DEFAULT_PORT=5000                    # 默认服务端口
SERVICE_NAME="realm-web"             # Systemd服务名
ADMIN_USER="admin"                   # 默认管理员用户名
DEPLOY_LOG="/var/log/realm-web-deploy.log"  # 部署日志
SERVICE_LOG="/var/log/realm-web-service.log" # 服务运行日志

# ===================== 颜色输出函数 =====================
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
blue() { echo -e "\033[34m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }
log() { echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" >> ${DEPLOY_LOG}; }

# ===================== 初始化日志 =====================
init_log() {
    if [ ! -f ${DEPLOY_LOG} ]; then
        touch ${DEPLOY_LOG} && chmod 644 ${DEPLOY_LOG}
    fi
    log "===================== Realm Web 部署开始 ====================="
    log "部署服务器：$(hostname -I | awk '{print $1}')"
    log "系统版本：$(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | sed 's/"//g')"
    green "✅ 部署日志已初始化：${DEPLOY_LOG}"
}

# ===================== 检查root权限 =====================
check_root() {
    info "🔍 检测用户权限..."
    log "当前用户UID：$(id -u)"
    if [ $(id -u) -ne 0 ]; then
        red "❌ 必须以root用户执行！请用 sudo -i 切换后重试"
        log "错误：非root用户执行，部署终止"
        exit 1
    fi
    green "✅ root权限验证通过"
    log "权限检查通过"
}

# ===================== 安装系统依赖 =====================
install_sys_deps() {
    info "🔍 安装系统基础依赖..."
    log "安装依赖：python3 python3-pip python3-venv git curl wget"
    if [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        yum install -y python3 python3-pip python3-venv git curl wget firewalld || {
            red "❌ CentOS依赖安装失败！"
            log "错误：CentOS安装系统依赖失败"
            exit 1
        }
        systemctl start firewalld && systemctl enable firewalld
    elif [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        apt update -y && apt install -y python3 python3-pip python3-venv git curl wget ufw || {
            red "❌ Debian/Ubuntu依赖安装失败！"
            log "错误：Debian/Ubuntu安装系统依赖失败"
            exit 1
        }
        ufw enable || true
    else
        red "❌ 不支持的系统（仅支持CentOS/Debian/Ubuntu）"
        log "错误：非兼容系统，部署终止"
        exit 1
    fi
    # 升级pip
    python3 -m pip install --upgrade pip -i https://pypi.tuna.tsinghua.edu.cn/simple || {
        red "❌ pip升级失败！"
        log "错误：pip升级失败"
        exit 1
    }
    green "✅ 系统依赖安装完成"
    log "系统依赖安装成功"
}

# ===================== 安装Realm =====================
install_realm() {
    info "🔍 检测Realm是否安装..."
    if command -v realm &>/dev/null; then
        green "✅ Realm已安装，版本：$(realm --version | head -1)"
        log "Realm已安装：$(realm --version | head -1)"
        return
    fi
    log "Realm未安装，执行官方安装脚本"
    curl -fsSL https://raw.githubusercontent.com/zhboner/realm/master/install.sh | bash || {
        red "❌ Realm安装失败！请手动执行：curl -fsSL https://raw.githubusercontent.com/zhboner/realm/master/install.sh | bash"
        log "错误：Realm安装脚本执行失败"
        exit 1
    }
    if command -v realm &>/dev/null; then
        green "✅ Realm安装成功：$(realm --version | head -1)"
        log "Realm安装成功"
    else
        red "❌ Realm安装后验证失败！"
        log "错误：Realm安装后未找到可执行文件"
        exit 1
    fi
}

# ===================== 拉取GitHub仓库代码 =====================
pull_github_code() {
    info "🔍 拉取GitHub仓库代码..."
    log "仓库地址：https://github.com/HYT-1840/realm-web-deploy"
    if [ -d ${DEPLOY_DIR} ]; then
        yellow "⚠️  部署目录已存在，将覆盖更新代码"
        log "部署目录已存在，执行git pull更新"
        cd ${DEPLOY_DIR} && git pull || {
            red "❌ git pull更新失败，将重新克隆"
            rm -rf ${DEPLOY_DIR}
            git clone https://github.com/HYT-1840/realm-web-deploy ${DEPLOY_DIR} || {
                red "❌ 仓库克隆失败！请检查网络或仓库地址"
                log "错误：git clone仓库失败"
                exit 1
            }
        }
    else
        git clone https://github.com/HYT-1840/realm-web-deploy ${DEPLOY_DIR} || {
            red "❌ 仓库克隆失败！请检查网络"
            log "错误：git clone仓库失败"
            exit 1
        }
    fi
    chmod -R 755 ${DEPLOY_DIR}
    green "✅ 代码拉取/更新完成：${DEPLOY_DIR}"
    log "GitHub仓库代码拉取成功"
}

# ===================== 交互式配置参数 =====================
get_config() {
    info "📝 配置部署参数（按回车使用默认值）"
    log "进入交互式配置"
    # 配置服务端口
    while true; do
        read -p "请输入Web服务端口 [默认：${DEFAULT_PORT}]：" INPUT_PORT
        PORT=${INPUT_PORT:-${DEFAULT_PORT}}
        if ! [[ ${PORT} =~ ^[0-9]+$ ]] || [ ${PORT} -lt 1024 ] || [ ${PORT} -gt 65535 ]; then
            red "❌ 端口必须是1024-65535的数字！"
            continue
        fi
        if ss -tuln | grep -q ":${PORT} "; then
            red "❌ 端口${PORT}已被占用，请更换！"
            continue
        fi
        break
    done
    # 配置管理员密码
    while true; do
        read -s -p "请输入${ADMIN_USER}的密码 [建议8位以上]：" ADMIN_PWD
        echo
        read -s -p "请再次输入密码：" ADMIN_PWD_CONFIRM
        echo
        if [ -z "${ADMIN_PWD}" ] || [ "${ADMIN_PWD}" != "${ADMIN_PWD_CONFIRM}" ]; then
            red "❌ 密码不能为空或两次输入不一致！"
            continue
        fi
        break
    done
    # 确认配置
    blue "📌 最终配置："
    echo "部署目录：${DEPLOY_DIR}"
    echo "服务端口：${PORT}"
    echo "管理员账号：${ADMIN_USER}"
    read -p "确认配置？[Y/n]：" CONFIRM
    CONFIRM=${CONFIRM:-Y}
    if [ "${CONFIRM^^}" != "Y" ]; then
        red "❌ 用户取消部署"
        log "错误：用户取消配置"
        exit 0
    fi
    green "✅ 配置确认完成"
    log "配置参数：端口=${PORT}，管理员=${ADMIN_USER}"
}

# ===================== 安装Python依赖 =====================
install_python_deps() {
    info "🐍 配置Python环境..."
    log "创建Python虚拟环境：${DEPLOY_DIR}/venv"
    # 创建虚拟环境
    python3 -m venv ${DEPLOY_DIR}/venv || {
        red "❌ 虚拟环境创建失败！"
        log "错误：创建Python虚拟环境失败"
        exit 1
    }
    # 安装依赖
    source ${DEPLOY_DIR}/venv/bin/activate
    log "安装Python依赖：flask flask-login psutil pyjwt flask-cors gunicorn"
    pip install flask flask-login psutil pyjwt flask-cors gunicorn -i https://pypi.tuna.tsinghua.edu.cn/simple || {
        red "❌ Python依赖安装失败！"
        log "错误：安装依赖失败"
        deactivate
        exit 1
    }
    # 初始化数据库（创建管理员）
    log "初始化数据库，创建管理员：${ADMIN_USER}"
    python ${DEPLOY_DIR}/app.py ${ADMIN_USER} ${ADMIN_PWD} || {
        red "❌ 数据库初始化失败！"
        log "错误：执行app.py初始化管理员失败"
        deactivate
        exit 1
    }
    deactivate
    green "✅ Python环境配置完成"
    log "Python依赖安装和数据库初始化成功"
}

# ===================== 创建Systemd服务 =====================
create_systemd() {
    info "⚙️ 创建Systemd服务（进程守护）..."
    log "创建服务文件：/etc/systemd/system/${SERVICE_NAME}.service"
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Realm Web Multi-User Management Panel
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${DEPLOY_DIR}
ExecStart=${DEPLOY_DIR}/venv/bin/gunicorn -w 4 -b 0.0.0.0:${PORT} app:app
Restart=on-failure
RestartSec=5s
StandardOutput=append:${SERVICE_LOG}
StandardError=append:${SERVICE_LOG}

[Install]
WantedBy=multi-user.target
EOF
    # 启动服务
    systemctl daemon-reload || {
        red "❌ Systemd重载失败！"
        log "错误：systemctl daemon-reload失败"
        exit 1
    }
    systemctl enable --now ${SERVICE_NAME} || {
        red "❌ 服务启动失败！"
        log "错误：启动${SERVICE_NAME}服务失败"
        exit 1
    }
    # 验证状态
    sleep 3
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        green "✅ ${SERVICE_NAME}服务启动成功（开机自启）"
        log "服务启动成功，已设置开机自启"
    else
        red "❌ 服务状态异常！执行 systemctl status ${SERVICE_NAME} 查看详情"
        log "错误：服务启动后非活跃状态"
        exit 1
    fi
}

# ===================== 防火墙放行 =====================
open_firewall() {
    info "🔥 放行服务端口${PORT}..."
    log "根据系统类型放行端口"
    if [ -f /etc/redhat-release ]; then
        firewall-cmd --add-port=${PORT}/tcp --permanent || {
            red "❌ firewalld放行失败！"
            log "错误：firewalld添加端口规则失败"
            exit 1
        }
        firewall-cmd --reload
    elif [ -f /etc/debian_version ]; then
        ufw allow ${PORT}/tcp || {
            red "❌ ufw放行失败！"
            log "错误：ufw添加端口规则失败"
            exit 1
        }
    fi
    green "✅ 防火墙已放行端口${PORT}/tcp"
    log "端口放行成功"
}

# ===================== 部署完成汇总 =====================
deploy_complete() {
    echo -e "\n"
    green "🎉 Realm Web面板部署完成！"
    log "部署全部步骤执行完成"
    blue "📌 访问信息："
    echo "访问地址：http://$(hostname -I | awk '{print $1}'):${PORT}"
    echo "管理员账号：${ADMIN_USER}"
    echo "管理员密码：你设置的密码"
    echo -e "\n"
    blue "📌 常用命令："
    echo "启动服务：systemctl start ${SERVICE_NAME}"
    echo "停止服务：systemctl stop ${SERVICE_NAME}"
    echo "重启服务：systemctl restart ${SERVICE_NAME}"
    echo "查看状态：systemctl status ${SERVICE_NAME}"
    echo "查看日志：tail -f ${SERVICE_LOG}"
    echo -e "\n"
    blue "📌 日志地址："
    echo "部署日志：${DEPLOY_LOG}"
    echo "服务日志：${SERVICE_LOG}"
    echo -e "\n"
    yellow "⚠️  注意：公网访问建议配置HTTPS，请勿泄露管理员密码"
}

# ===================== 主执行流程 =====================
main() {
    clear
    echo -e "============================================="
    echo -e "     Realm Web 多用户管理面板 - 自动部署脚本"
    echo -e "     仓库地址：https://github.com/HYT-1840/realm-web-deploy"
    echo -e "=============================================\n"
    # 执行步骤
    init_log
    check_root
    install_sys_deps
    install_realm
    get_config
    pull_github_code
    install_python_deps
    create_systemd
    open_firewall
    deploy_complete
}

# 启动部署
main "$@"

