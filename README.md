Realm Web Rust
 
轻量、高性能、无依赖的Realm端口转发管理面板，Rust语言重构版，彻底告别Python环境限制，单二进制文件一键运行。
 
项目特性
 
- 纯Rust编写，静态编译单文件，无任何运行时依赖
- 原生解决Debian/Ubuntu PEP 668系统Python环境限制
- 内存安全、无泄漏、低资源占用，低配VPS流畅运行
- 100%兼容原版数据库、前端模板、API接口
- 内置用户登录、权限控制、端口规则管理、进程守护
- 搭配Caddy自动HTTPS，一键部署生产环境
 
系统要求
 
- Linux x86_64 / aarch64
- 已安装Realm转发核心（脚本自动安装）
- root权限运行
 
快速部署
 
bash
  
# 克隆项目
git clone https://github.com/xxx/realm-web-deploy.git
cd realm-web-deploy

# 赋予执行权限
chmod +x deploy.sh

# 一键全自动部署
./deploy.sh
 
 
按照提示输入端口、管理员账号、密码、域名，脚本自动完成依赖安装、编译、数据库初始化、Systemd服务配置与HTTPS代理。
 
访问与管理
 
- 访问地址： https://你的域名 
- 服务管理： systemctl {start|stop|restart|status} realm-web 
- 查看日志： journalctl -u realm-web -f 
 
目录说明
 
plaintext
  
├── rust/           Rust源码与编译配置
├── templates/     前端页面模板（兼容原版）
├── caddy/         Caddy HTTPS配置模板
├── deploy.sh      一键部署脚本
└── realm-web-rust 编译后二进制主程序
 
 
编译说明
 
本地跨平台编译（推荐）
 
bash
  
cd rust
cross build --release --target x86_64-unknown-linux-gnu
 
 
生成文件： rust/target/x86_64-unknown-linux-gnu/release/realm-web-rust 
 
VPS本地编译
 
bash
  
cd rust
cargo build --release
 
 
常见问题
 
1. externally-managed-environment：本项目无Python依赖，彻底规避该错误
2. 端口无法访问：脚本已自动加固防火墙，仅允许通过HTTPS 443访问
3. 服务启动失败：使用 journalctl -u realm-web -f 查看运行日志
 
许可证
 
MIT./deploy.sh


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
