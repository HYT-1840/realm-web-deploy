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

# 1. 切换root权限

sudo -i
# 2. 克隆整合后的项目（确保包含caddy目录和修改后的deploy.sh）

git clone https://github.com/HYT-1840/realm-web-deploy.git

cd realm-web-deploy

# 3. 赋予执行权限

chmod +x deploy.sh

# 4. 一键部署（仅需输入4个参数，全程自动）

./deploy.sh


realm-web-deploy/
├── deploy.sh          # 主部署脚本（仅少量修改，删除Python逻辑）
├── caddy/             # 原有Caddy配置模板（无需任何修改）
├── templates/         # 原有前端模板（index.html/login.html，直接复用）
├── rust/              # 新增Rust项目目录（核心重构代码）
│   ├── Cargo.toml     # Rust依赖管理（类似Python的requirements.txt）
│   ├── Cargo.lock     # 依赖校验文件（自动生成）
│   └── src/           # 源码目录
│       ├── main.rs    # 入口文件（Web服务启动/路由注册）
│       ├── db.rs      # 数据库操作（SQLite初始化/增删改查）
│       ├── process.rs # 进程管理（Realm启动/停止/守护）
│       ├── auth.rs    # 认证模块（登录/登出/权限控制）
│       └── models.rs  # 数据模型（与SQLite表结构一一对应）
└── README.md          # 部署说明（可选更新）
