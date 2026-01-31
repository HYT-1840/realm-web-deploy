#!/bin/bash
set -e

# ==================== 版本信息配置区（可自定义）====================
SCRIPT_NAME="Realm Web Rust 面板管理中心"
VERSION="v1.2.0"
RELEASE_DATE="2026-01-31"
AUTHOR="HYT-1840"
# ===================================================================

# 颜色输出函数（与其他脚本保持一致，保证输出美观）
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }

# 显示版本+菜单（核心展示函数，格式美观）
show_menu() {
    clear
    echo "================================================================"
    echo -e "           ${SCRIPT_NAME} [${VERSION}]"
    echo -e "           更新: ${RELEASE_DATE} | 作者: ${AUTHOR}"
    echo "================================================================"
    echo "  1. 全新安装部署面板"
    echo "  2. 卸载面板（保留数据库/转发规则）"
    echo "  3. 启动面板服务"
    echo "  4. 停止面板服务"
    echo "  5. 重启面板服务"
    echo "  6. 查看面板实时运行日志"
    echo "  7. 查看Caddy反向代理日志"
    echo "  0. 退出管理中心"
    echo "================================================================"
    read -p "请输入操作序号 [0-7]：" choice
}

# 检查root权限（所有操作均需root，统一校验）
check_root() {
    if [[ $EUID -ne 0 ]]; then
        red "❌ 所有操作均需root权限执行！"
        red "👉 请先执行：sudo -i 切换root后再运行"
        exit 1
    fi
}

# 检查独立脚本是否存在（防止误删脚本导致调用失败）
check_scripts() {
    local script_list=("install.sh" "uninstall.sh" "start.sh" "stop.sh" "restart.sh" "log-panel.sh" "log-caddy.sh")
    for script in "${script_list[@]}"; do
        if [[ ! -f "./$script" ]]; then
            red "❌ 缺失核心脚本：$script"
            red "👉 请检查项目文件是否完整，重新上传缺失脚本"
            exit 1
        fi
        # 确保脚本有执行权限（自动修复，提升容错）
        chmod +x "./$script" 2>/dev/null || true
    done
}

# 主调度逻辑（根据选择调用对应独立脚本，核心核心！）
main() {
    # 前置校验：权限+脚本完整性
    check_root
    check_scripts

    # 菜单循环（轻量循环，仅做选择，无阻塞）
    while true; do
        show_menu
        case $choice in
            1)
                info "🚀 正在调用安装脚本...\n"
                ./install.sh  # 调用独立安装脚本
                read -p "\n✅ 安装流程执行完成，按回车返回菜单..." tmp
                ;;
            2)
                info "⚠️  正在调用卸载脚本...\n"
                ./uninstall.sh  # 调用独立卸载脚本
                read -p "\n✅ 卸载流程执行完成，按回车返回菜单..." tmp
                ;;
            3)
                info "▶️  正在调用启动脚本...\n"
                ./start.sh  # 调用独立启动脚本
                read -p "\n✅ 启动流程执行完成，按回车返回菜单..." tmp
                ;;
            4)
                info "⏹️  正在调用停止脚本...\n"
                ./stop.sh  # 调用独立停止脚本
                read -p "\n✅ 停止流程执行完成，按回车返回菜单..." tmp
                ;;
            5)
                info "🔄  正在调用重启脚本...\n"
                ./restart.sh  # 调用独立重启脚本
                read -p "\n✅ 重启流程执行完成，按回车返回菜单..." tmp
                ;;
            6)
                info "📜  正在调用面板日志脚本（按Ctrl+C退出，返回菜单）...\n"
                ./log-panel.sh  # 调用独立面板日志脚本
                echo -e "\n✅ 日志查看已退出，返回菜单..."
                sleep 1
                ;;
            7)
                info "📜  正在调用Caddy日志脚本（按Ctrl+C退出，返回菜单）...\n"
                ./log-caddy.sh  # 调用独立Caddy日志脚本
                echo -e "\n✅ 日志查看已退出，返回菜单..."
                sleep 1
                ;;
            0)
                clear
                green "👋 退出 ${SCRIPT_NAME} [${VERSION}]"
                green "💡 如需再次使用，执行：./main.sh 即可"
                exit 0
                ;;
            *)
                red "❌ 输入无效！请输入0-7之间的有效序号"
                read -p "按回车返回菜单重新输入..." tmp
                ;;
        esac
    done
}

# 执行主调度逻辑
main
