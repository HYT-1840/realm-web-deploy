# Realm Web 多用户管理面板
基于 Flask + Realm 实现的**多用户流量转发管理面板**，支持 Web 可视化操作，无需复杂命令行，适配 Linux 服务器，可快速实现多用户隔离、转发规则管控。

## 项目功能
✅ 多用户隔离：子用户仅管理自己的转发规则，互不干扰  
✅ 可视化管控：Web 页面创建/启动/停止/删除转发规则  
✅ 进程守护：Systemd 托管服务，自动重启，开机自启  
✅ 一键部署：交互式脚本，自动安装依赖、拉取代码、配置服务  
✅ 详细日志：部署/运行日志分离，方便问题排查  

## 支持环境
- 操作系统：CentOS 7+/Debian 10+/Ubuntu 18.04+  
- 依赖：Python 3.8+、Realm（脚本自动安装）

## 安装方式

- 方式 1：克隆仓库后执行（推荐，完整拉取项目文件）
适用于需要完整项目文件的场景，执行以下 3 条命令即可（Linux 环境，需 root 权限，先执行 sudo -i 切换）：
# 1. 克隆GitHub仓库到本地
git clone https://github.com/HYT-1840/realm-web-deploy.git
# 2. 进入仓库目录
cd realm-web-deploy
# 3. 赋予脚本执行权限并运行交互式部署脚本
chmod +x deploy.sh && ./deploy.sh

- 方式 2：直接下载单个 deploy.sh 脚本执行（轻量，仅获取部署脚本）
适用于快速执行部署、无需本地保留完整项目文件的场景，执行以下 2 条命令（Linux 环境，root 权限）：
# 1. 直接下载deploy.sh脚本到当前目录（使用curl）
curl -O https://raw.githubusercontent.com/HYT-1840/realm-web-deploy/master/deploy.sh
# 2. 赋予执行权限并运行
chmod +x deploy.sh && ./deploy.sh
补充：若 curl 下载失败（网络问题）
替换为 wget 命令下载脚本：
wget https://raw.githubusercontent.com/HYT-1840/realm-web-deploy/master/deploy.sh
chmod +x deploy.sh && ./deploy.sh

关键执行说明
权限要求：必须以 root 用户执行（脚本涉及环境安装、端口配置、Systemd 服务创建），非 root 用户先执行 sudo -i 切换；
交互式操作：运行 ./deploy.sh 后，脚本会自动引导配置（仅需输入 2 个参数）：
自定义 Web 面板端口（默认 5000，自动检测端口占用）；
管理员密码（输入隐藏，需二次确认，建议 8 位以上）；
自动完成：配置完成后，脚本会全自动执行：环境依赖安装 → Realm 安装 → 项目部署 → Systemd 服务创建 → 防火墙放行，无需手动干预；
部署完成：脚本最终会输出面板访问地址、管理员账号等关键信息，直接浏览器访问即可使用。
