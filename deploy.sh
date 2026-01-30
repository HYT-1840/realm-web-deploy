#!/bin/bash
set -euo pipefail

# ===================== 基础配置（可修改）=====================
DEPLOY_DIR="/opt/realm-web"          # 部署目录
DEFAULT_PORT=5000                    # 默认服务端口
SERVICE_NAME="realm-web"             # Systemd服务名
ADMIN_USER="admin"                   # 默认管理员用户名
DEPLOY_LOG="/var/log/realm-web-deploy.log"  # 部署日志
SERVICE_LOG="/var/log/realm-web-service.log" # 服务运行日志
GITHUB_REPO="https://github.com/HYT-1840/realm-web-deploy"  # 代码仓库地址

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
        mkdir -p $(dirname ${DEPLOY_LOG})
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

# ===================== 检查系统兼容性 =====================
check_system() {
    info "🔍 检测系统兼容性..."
    if [ -f /etc/redhat-release ]; then
        OS_TYPE="centos"
        log "检测到CentOS/RHEL系统"
    elif [ -f /etc/debian_version ]; then
        OS_TYPE="debian"
        log "检测到Debian/Ubuntu系统"
    else
        red "❌ 不支持的系统（仅支持CentOS 7+/Debian 9+/Ubuntu 18.04+）"
        log "错误：非兼容系统，部署终止"
        exit 1
    fi
    green "✅ 系统兼容性验证通过"
}

# ===================== 安装系统依赖 =====================
install_sys_deps() {
    info "🔍 安装系统基础依赖..."
    log "安装依赖：python3 python3-pip python3-venv git curl wget procps"
    if [ ${OS_TYPE} == "centos" ]; then
        # CentOS/RHEL
        yum install -y epel-release || true
        yum install -y python3 python3-pip python3-venv git curl wget procps firewalld || {
            red "❌ CentOS依赖安装失败！"
            log "错误：CentOS安装系统依赖失败"
            exit 1
        }
        systemctl start firewalld && systemctl enable firewalld || true
    else
        # Debian/Ubuntu
        apt update -y && apt install -y python3 python3-pip python3-venv git curl wget procps ufw || {
            red "❌ Debian/Ubuntu依赖安装失败！"
            log "错误：Debian/Ubuntu安装系统依赖失败"
            exit 1
        }
        ufw enable || true
    fi
    # 升级pip并配置国内源
    python3 -m pip install --upgrade pip -i https://pypi.tuna.tsinghua.edu.cn/simple || {
        red "❌ pip升级失败！"
        log "错误：pip升级失败"
        exit 1
    }
    # 配置pip国内源
    mkdir -p /root/.config/pip
    cat > /root/.config/pip/pip.conf << EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
[install]
trusted-host = pypi.tuna.tsinghua.edu.cn
EOF
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
    # 国内镜像安装（备用）
    if ! curl -fsSL https://raw.githubusercontent.com/zhboner/realm/master/install.sh | bash; then
        yellow "⚠️  官方安装脚本失败，尝试国内镜像..."
        if ! curl -fsSL https://gitee.com/mirrors/realm/raw/master/install.sh | bash; then
            red "❌ Realm安装失败！请手动执行：curl -fsSL https://raw.githubusercontent.com/zhboner/realm/master/install.sh | bash"
            log "错误：Realm安装脚本执行失败"
            exit 1
        fi
    fi
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
    log "仓库地址：${GITHUB_REPO}"
    # 安装git（防止未安装）
    if ! command -v git &>/dev/null; then
        if [ ${OS_TYPE} == "centos" ]; then
            yum install -y git
        else
            apt install -y git
        fi
    fi
    if [ -d ${DEPLOY_DIR} ]; then
        yellow "⚠️  部署目录已存在，将覆盖更新代码"
        log "部署目录已存在，执行git pull更新"
        cd ${DEPLOY_DIR} && git pull || {
            red "❌ git pull更新失败，将重新克隆"
            log "git pull失败，删除目录重新克隆"
            rm -rf ${DEPLOY_DIR}
            git clone ${GITHUB_REPO} ${DEPLOY_DIR} || {
                red "❌ 仓库克隆失败！请检查网络或仓库地址"
                log "错误：git clone仓库失败"
                exit 1
            }
        }
    else
        git clone ${GITHUB_REPO} ${DEPLOY_DIR} || {
            red "❌ 仓库克隆失败！请检查网络"
            log "错误：git clone仓库失败"
            exit 1
        }
    fi
    # 确保templates目录存在
    mkdir -p ${DEPLOY_DIR}/templates
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
        if [ -z "${ADMIN_PWD}" ]; then
            red "❌ 密码不能为空！"
            continue
        fi
        if [ "${ADMIN_PWD}" != "${ADMIN_PWD_CONFIRM}" ]; then
            red "❌ 两次输入的密码不一致！"
            continue
        fi
        if [ ${#ADMIN_PWD} -lt 6 ]; then
            yellow "⚠️  密码长度小于6位，是否继续？[Y/n]"
            read CONFIRM_SHORT_PWD
            CONFIRM_SHORT_PWD=${CONFIRM_SHORT_PWD:-Y}
            if [ "${CONFIRM_SHORT_PWD^^}" != "Y" ]; then
                continue
            fi
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
    # 激活虚拟环境并安装依赖
    source ${DEPLOY_DIR}/venv/bin/activate
    log "安装Python依赖：flask flask-login psutil flask-cors gunicorn"
    pip install flask flask-login psutil flask-cors gunicorn -i https://pypi.tuna.tsinghua.edu.cn/simple || {
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
    # 停止现有服务（如果存在）
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        systemctl stop ${SERVICE_NAME}
        log "停止现有${SERVICE_NAME}服务"
    fi
    # 写入服务文件
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Realm Web Multi-User Management Panel
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${DEPLOY_DIR}
Environment="REALM_SECRET_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
Environment="REALM_PORT=${PORT}"
ExecStart=${DEPLOY_DIR}/venv/bin/gunicorn -w 4 -b 0.0.0.0:${PORT} --timeout 60 app:app
Restart=on-failure
RestartSec=5s
StandardOutput=append:${SERVICE_LOG}
StandardError=append:${SERVICE_LOG}
LimitNOFILE=65535

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
    if [ ${OS_TYPE} == "centos" ]; then
        firewall-cmd --add-port=${PORT}/tcp --permanent || {
            red "❌ firewalld放行失败！"
            log "错误：firewalld添加端口规则失败"
            exit 1
        }
        firewall-cmd --reload
    else
        ufw allow ${PORT}/tcp || {
            red "❌ ufw放行失败！"
            log "错误：ufw添加端口规则失败"
            exit 1
        }
        ufw reload
    fi
    green "✅ 防火墙已放行端口${PORT}/tcp"
    log "端口放行成功"
}

# ===================== 部署完成提示 =====================
deploy_complete() {
    green "🎉 Realm Web管理面板部署完成！"
    blue "📢 访问地址：http://$(hostname -I | awk '{print $1}'):${PORT}"
    blue "🔑 管理员账号：${ADMIN_USER}"
    yellow "⚠️  请立即登录并修改管理员密码！"
    log "部署完成，访问地址：http://$(hostname -I | awk '{print $1}'):${PORT}"
    log "===================== Realm Web 部署结束 ====================="
}

# ===================== 主流程 =====================
main() {
    init_log
    check_root
    check_system
    install_sys_deps
    install_realm
    pull_github_code
    get_config
    install_python_deps
    create_systemd
    open_firewall
    deploy_complete
}

# 执行主流程
main
``{insert\_element\_2\_YAoKIyMjIOS4ieOAgeWujOaVtCA=}`index.html` 代码（修复语法错误+优化体验）
```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Realm管理面板 - 主界面</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { 
            background: #f5f7fa; 
            font-size: 14px;
        }
        .card { 
            box-shadow: 0 2px 10px rgba(0,0,0,0.1); 
            margin-bottom: 20px;
            border: none;
            border-radius: 8px;
        }
        .card-header {
            background: #fff;
            border-bottom: 1px solid #eee;
            border-radius: 8px 8px 0 0 !important;
            padding: 15px 20px;
            font-weight: 600;
        }
        .card-body {
            padding: 20px;
        }
        .operation-btn { 
            margin: 0 2px;
            padding: 2px 8px;
        }
        .badge {
            font-size: 12px;
            padding: 5px 8px;
        }
        .form-control {
            border-radius: 6px;
            border: 1px solid #ddd;
        }
        .btn {
            border-radius: 6px;
        }
        .table {
            --bs-table-hover-bg: #f8f9fa;
        }
        .table th {
            font-weight: 600;
            color: #666;
        }
        .alert {
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 9999;
            min-width: 300px;
            display: none;
        }
    </style>
</head>
<body>
    <!-- 全局提示框 -->
    <div class="alert alert-success alert-dismissible fade show" id="globalAlert">
        <span id="alertMsg"></span>
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
    </div>

    <div class="container mt-4">
        <div class="row">
            <div class="col-12 d-flex justify-content-between align-items-center mb-4">
                <h3 class="mb-0">Realm流量转发管理面板</h3>
                <div class="d-flex align-items-center">
                    <span class="me-3">当前登录：<b id="username"></b></span>
                    <button class="btn btn-outline-danger btn-sm" id="logoutBtn">登出</button>
                </div>
            </div>

            <!-- 添加子用户 -->
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">添加子用户</div>
                    <div class="card-body">
                        <form id="addUserForm">
                            <div class="row g-3">
                                <div class="col-6">
                                    <input type="text" class="form-control" name="username" placeholder="子用户名（至少3位）" required minlength="3">
                                </div>
                                <div class="col-6">
                                    <input type="password" class="form-control" name="password" placeholder="子用户密码（至少6位）" required minlength="6">
                                </div>
                                <div class="col-12">
                                    <button type="submit" class="btn btn-primary w-100">创建子用户</button>
                                </div>
                            </div>
                        </form>
                    </div>
                </div>
            </div>

            <!-- 添加转发规则 -->
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">添加转发规则</div>
                    <div class="card-body">
                        <form id="addRuleForm">
                            <div class="row g-3">
                                <div class="col-5">
                                    <input type="number" class="form-control" name="local_port" placeholder="本地监听端口" min="1024" max="65535" required>
                                </div>
                                <div class="col-7">
                                    <input type="text" class="form-control" name="target" placeholder="目标地址(例：192.168.1.100:80)" required>
                                </div>
                                <div class="col-12">
                                    <button type="submit" class="btn btn-success w-100">添加转发规则</button>
                                </div>
                            </div>
                        </form>
                    </div>
                </div>
            </div>

            <!-- 转发规则列表 -->
            <div class="col-12">
                <div class="card">
                    <div class="card-header">我的转发规则</div>
                    <div class="card-body p-0">
                        <div class="table-responsive">
                            <table class="table table-bordered table-hover mb-0">
                                <thead class="table-light">
                                    <tr>
                                        <th>ID</th>
                                        <th>本地监听端口</th>
                                        <th>目标地址</th>
                                        <th>进程ID</th>
                                        <th>运行状态</th>
                                        <th>操作</th>
                                    </tr>
                                </thead>
                                <tbody id="ruleTableBody">
                                    <tr><td colspan="6" class="text-center text-muted py-3">暂无转发规则</td></tr>
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/jquery@3.7.0/dist/jquery.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        $(function() {
            // 初始化用户名
            const username = '{{ username }}';
            $('#username').text(username);

            // 加载当前用户的规则列表
            loadRules();

            // 全局提示框函数
            function showAlert(msg, type = 'success') {
                const $alert = $('#globalAlert');
                $alert.removeClass('alert-success alert-danger alert-warning').addClass(`alert-${type}`);
                $('#alertMsg').text(msg);
                $alert.fadeIn();
                setTimeout(() => {
                    $alert.fadeOut();
                }, 3000);
            }

            // 登出功能
            $('#logoutBtn').on('click', function() {
                if (confirm('确定要登出吗？')) {
                    $.ajax({
                        url: '/api/logout',
                        type: 'POST',
                        dataType: 'json',
                        success: function(res) {
                            showAlert(res.msg);
                            setTimeout(() => {
                                window.location.href = '/login';
                            }, 1000);
                        },
                        error: function() {
                            showAlert('登出请求失败', 'danger');
                        }
                    });
                }
            });

            // 添加子用户
            $('#addUserForm').on('submit', function(e) {
                e.preventDefault();
                const formData = $(this).serializeArray();
                const data = {};
                formData.forEach(item => {
                    data[item.name] = item.value.trim();
                });
                
                $.ajax({
                    url: '/api/add_user',
                    type: 'POST',
                    contentType: 'application/json',
                    data: JSON.stringify(data),
                    dataType: 'json',
                    success: function(res) {
                        if (res.code === 0) {
                            showAlert(res.msg);
                            $('#addUserForm')[0].reset();
                        } else {
                            showAlert(res.msg, 'danger');
                        }
                    },
                    error: function() {
                        showAlert('请求失败，请重试', 'danger');
                    }
                });
            });

            // 添加转发规则
            $('#addRuleForm').on('submit', function(e) {
                e.preventDefault();
                const formData = $(this).serializeArray();
                const data = {};
                formData.forEach(item => {
                    data[item.name] = item.value.trim();
                });
                
                $.ajax({
                    url: '/api/add_rule',
                    type: 'POST',
                    contentType: 'application/json',
                    data: JSON.stringify(data),
                    dataType: 'json',
                    success: function(res) {
                        if (res.code === 0) {
                            showAlert(res.msg);
                            $('#addRuleForm')[0].reset();
                            loadRules(); // 刷新规则列表
                        } else {
                            showAlert(res.msg, 'danger');
                        }
                    },
                    error: function() {
                        showAlert('请求失败，请重试', 'danger');
                    }
                });
            });

            // 启动规则
            $(document).on('click', '.startRuleBtn', function() {
                const ruleId = $(this).data('id');
                operateRule(ruleId, 'start_rule', '启动');
            });

            // 停止规则
            $(document).on('click', '.stopRuleBtn', function() {
                const ruleId = $(this).data('id');
                operateRule(ruleId, 'stop_rule', '停止');
            });

            // 删除规则
            $(document).on('click', '.deleteRuleBtn', function() {
                const ruleId = $(this).data('id');
                if (confirm('确定要删除该规则吗？会自动停止对应进程！')) {
                    operateRule(ruleId, 'delete_rule', '删除');
                }
            });

            // 通用规则操作函数
            function operateRule(ruleId, api, action) {
                $.ajax({
                    url: `/api/${api}`,
                    type: 'POST',
                    contentType: 'application/json',
                    data: JSON.stringify({ rule_id: ruleId }),
                    dataType: 'json',
                    success: function(res) {
                        if (res.code === 0) {
                            showAlert(res.msg);
                            loadRules(); // 操作成功后刷新列表
                        } else {
                            showAlert(res.msg, 'danger');
                        }
                    },
                    error: function() {
                        showAlert(`${action}请求失败，请重试`, 'danger');
                    }
                });
            }

            // 加载规则列表
            function loadRules() {
                $.ajax({
                    url: '/api/get_rules',
                    type: 'GET',
                    dataType: 'json',
                    success: function(res) {
                        if (res.code === 0) {
                            const $tbody = $('#ruleTableBody');
                            $tbody.empty();
                            
                            if (res.data.length === 0) {
                                $tbody.append('<tr><td colspan="6" class="text-center text-muted py-3">暂无转发规则</td></tr>');
                                return;
                            }

                            // 渲染规则数据
                            res.data.forEach(rule => {
                                const statusBadge = rule.status === 'run' 
                                    ? '<span class="badge bg-success">运行中</span>' 
                                    : '<span class="badge bg-secondary">已停止</span>';
                                
                                const startBtn = rule.status === 'stop' 
                                    ? `<button class="btn btn-sm btn-success operation-btn startRuleBtn" data-id="${rule.id}">启动</button>` 
                                    : '';
                                
                                const stopBtn = rule.status === 'run' 
                                    ? `<button class="btn btn-sm btn-warning operation-btn stopRuleBtn" data-id="${rule.id}">停止</button>` 
                                    : '';

                                $tbody.append(`
                                    <tr>
                                        <td>${rule.id}</td>
                                        <td>${rule.local_port}</td>
                                        <td>${rule.target}</td>
                                        <td>${rule.pid || '-'}</td>
                                        <td>${statusBadge}</td>
                                        <td>
                                            ${startBtn}
                                            ${stopBtn}
                                            <button class="btn btn-sm btn-danger operation-btn deleteRuleBtn" data-id="${rule.id}">删除</button>
                                        </td>
                                    </tr>
                                `);
                            });
                        } else {
                            showAlert('加载规则失败', 'danger');
                        }
                    },
                    error: function() {
                        showAlert('加载规则请求失败', 'danger');
                    }
                });
            }

            // 监听表单输入验证
            $('input[required]').on('blur', function() {
                if (!$(this).val().trim()) {
                    $(this).addClass('is-invalid');
                } else {
                    $(this).removeClass('is-invalid');
                }
            });
        });
    </script>
</body>
</html>
