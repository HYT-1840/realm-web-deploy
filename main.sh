#!/bin/bash
set -e

# ==================== 版本信息配置区 ====================
SCRIPT_NAME="Realm Web Rust 面板管理中心"
VERSION="v1.3.0"
RELEASE_DATE="2026-01-31"
AUTHOR="HYT-1840"
# =======================================================

# 颜色输出函数
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }

# 显示版本+菜单
show_menu() {
    echo "================================================================"
    echo -e "           ${SCRIPT_NAME} [${VERSION}]"
    echo -e "           更新: ${RELEASE_DATE} | 作者: ${AUTHOR}"
    echo "================================================================"
    echo "  1. 全新安装部署面板"
    echo "  2. 卸载面板（可选保留/删除数据库）"
    echo "  3. 启动面板服务"
    echo "  4. 停止面板服务"
    echo "  5. 重启面板服务"
    echo "  6. 查看面板实时日志（可选指定行数）"
    echo "  7. 查看Caddy反向代理日志（可选指定行数）"
    echo "  0. 退出管理中心"
    echo "================================================================"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        red "❌ 所有操作均需root权限执行！"
        red "👉 请先执行：sudo -i 切换root后再运行"
        exit 1
    fi
}

# 检查独立脚本完整性+赋权
check_scripts() {
    local script_list=("install.sh" "uninstall.sh" "start.sh" "stop.sh" "restart.sh" "log-panel.sh" "log-caddy.sh")
    for script in "${script_list[@]}"; do
        if [[ ! -f "./$script" ]]; then
            red "❌ 缺失核心脚本：$script"
            red "👉 请检查项目文件是否完整，重新上传缺失脚本"
            exit 1
        fi
        chmod +x "./$script" 2>/dev/null || true
    done
    # 检查Caddy模板目录
    [[ ! -d "./caddy" || ! -f "./caddy/Caddyfile.tpl" ]] && { red "❌ 缺失Caddy配置模板：caddy/Caddyfile.tpl"; exit 1; }
}

# 主调度逻辑
main() {
    check_root
    check_scripts

    while true; do
        clear
        show_menu
        read -p "请输入操作序号 [0-7]：" choice
        case $choice in
            1)
                clear
                show_menu
                info "📦 配置部署参数（按回车使用默认值）\n"
                # 1. 统一收集参数，导出为环境变量（全局传递给install.sh）
                read -p "🔧 面板运行端口（默认5000）：" PORT
                export PORT=${PORT:-5000}
                read -p "🔑 管理员用户名（默认admin）：" ADMIN_USER
                export ADMIN_USER=${ADMIN_USER:-admin}
                # 密码隐式输入+长度校验
                read -s -p "🔐 管理员密码（至少6位）：" ADMIN_PWD
                echo
                while [[ ${#ADMIN_PWD} -lt 6 ]]; do
                    red "❌ 密码长度不足6位！"
                    read -s -p "🔐 重新输入管理员密码：" ADMIN_PWD
                    echo
                done
                export ADMIN_PWD
                # 域名必填校验
                read -p "🌐 已解析的域名（必填）：" DOMAIN
                while [[ -z $DOMAIN ]]; do
                    red "❌ 域名不能为空！"
                    read -p "🌐 重新输入已解析的域名：" DOMAIN
                done
                export DOMAIN

                # 2. 参数确认（防止输入错误）
                echo -e "\n================================================================"
                green "✅ 部署参数确认："
                echo -e "   面板端口：$PORT | 管理员账号：$ADMIN_USER"
                echo -e "   访问域名：$DOMAIN | 密码：*******（已隐藏）"
                echo "================================================================"
                read -p "确认使用以上参数安装？[Y/n] " CONFIRM
                [[ $CONFIRM == "n" || $CONFIRM == "N" ]] && { yellow "❌ 已取消安装，返回菜单"; read -p "按回车继续..." tmp; break; }

                # 3. 调用安装脚本，环境变量自动传递
                info "\n🚀 正在执行安装流程，参数已通过环境变量传递...\n"
                ./install.sh
                # 安装完成清除敏感密码环境变量
                unset ADMIN_PWD
                read -p "\n✅ 安装流程执行完成，按回车返回菜单..." tmp
                ;;
            2)
                clear
                show_menu
                info "⚠️  配置卸载参数\n"
                # 选择卸载模式，传递命令行参数给uninstall.sh
                read -p "🔧 是否保留数据库/转发规则？[Y/n] " KEEP_DATA
                if [[ $KEEP_DATA == "n" || $KEEP_DATA == "N" ]]; then
                    UNINSTALL_MODE="delete"
                    yellow "⚠️  警告：选择删除模式，数据库/日志将被彻底清除，数据不可恢复！"
                else
                    UNINSTALL_MODE="keep"
                    green "✅ 选择保留模式，仅卸载面板程序，数据库/转发规则将保留"
                fi
                read -p "最终确认执行卸载操作？[y/N] " CONFIRM
                [[ $CONFIRM != "y" && $CONFIRM != "Y" ]] && { yellow "❌ 已取消卸载，返回菜单"; read -p "按回车继续..." tmp; break; }

                # 调用卸载脚本，传递命令行参数
                info "\n🚀 正在执行卸载流程，模式：$UNINSTALL_MODE...\n"
                ./uninstall.sh $UNINSTALL_MODE
                read -p "\n✅ 卸载流程执行完成，按回车返回菜单..." tmp
                ;;
            3)
                clear
                show_menu
                info "▶️  正在启动Realm Web面板服务...\n"
                ./start.sh
                read -p "\n✅ 启动流程执行完成，按回车返回菜单..." tmp
                ;;
            4)
                clear
                show_menu
                info "⏹️  正在停止Realm Web面板服务...\n"
                ./stop.sh
                read -p "\n✅ 停止流程执行完成，按回车返回菜单..." tmp
                ;;
            5)
                clear
                show_menu
                info "🔄  正在重启Realm Web面板服务...\n"
                ./restart.sh
                read -p "\n✅ 重启流程执行完成，按回车返回菜单..." tmp
                ;;
            6)
                clear
                show_menu
                info "📜  配置面板日志查看参数\n"
                read -p "🔢 查看日志行数（默认0=实时滚动，输入数字如200则显示最后200行）：" LOG_LINES
                LOG_LINES=${LOG_LINES:-0}
                info "\n🚀 正在查看面板日志（按Ctrl+C退出），参数：行数=$LOG_LINES...\n"
                # 调用日志脚本，传递命令行参数
                ./log-panel.sh $LOG_LINES
                echo -e "\n✅ 日志查看已退出，返回菜单..."
                sleep 1
                ;;
            7)
                clear
                show_menu
                info "📜  配置Caddy日志查看参数\n"
                read -p "🔢 查看日志行数（默认0=实时滚动，输入数字如200则显示最后200行）：" LOG_LINES
                LOG_LINES=${LOG_LINES:-0}
                info "\n🚀 正在查看Caddy日志（按Ctrl+C退出），参数：行数=$LOG_LINES...\n"
                # 调用日志脚本，传递命令行参数
                ./log-caddy.sh $LOG_LINES
                echo -e "\n✅ 日志查看已退出，返回菜单..."
                sleep 1
                ;;
            0)
                clear
                green "👋 退出 ${SCRIPT_NAME} [${VERSION}]"
                green "💡 如需再次使用，执行：cd /root/realm-web-deploy && ./main.sh"
                exit 0
                ;;
            *)
                red "❌ 输入无效！请输入0-7之间的有效序号"
                read -p "按回车返回菜单重新输入..." tmp
                ;;
        esac
    done
}

# 执行主逻辑
main
