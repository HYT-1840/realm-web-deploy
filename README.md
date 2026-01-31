Rust 版 Realm Web 面板部署步骤，适配 Debian / Ubuntu 系统。
 
一、前置说明
 
- 环境：Linux x86_64 / aarch64，Debian 10+ / Ubuntu 20.04+
- 权限：必须 root
- 项目结构：包含  rust/ 、 templates/ 、 caddy/ 、 deploy.sh 
- 产物：单二进制文件  realm-web-rust ，无运行依赖
 
二、完整部署步骤（按顺序执行）
 
1. 登录服务器并切换 root
 
bash
  
sudo -i
 
 
2. 下载/上传项目到服务器
 
方式A（git 克隆，示例地址自行替换）
 
bash
  
git clone https://github.com/你的用户名/realm-web-deploy.git
cd realm-web-deploy
 
 
方式B（本地打包上传）
 
- 本地打包项目目录 → 上传到服务器  /root/realm-web-deploy 
- 服务器进入目录：
 
bash
  
cd /root/realm-web-deploy
 
 
3. 给部署脚本加执行权限
 
bash
  
chmod +x deploy.sh
 
 
4. 执行一键部署脚本
 
bash
  
./deploy.sh
 
 
脚本交互时需要输入的内容（按提示填）
 
- 面板端口：默认  5000 ，直接回车即可
- 管理员用户名：默认  admin ，可自定义
- 管理员密码：至少6位
- 域名：必须已解析到当前服务器公网 IP
 
后续全自动执行：
 
- 安装系统依赖（git、curl、wget、sqlite 开发库等）
- 安装 realm 转发二进制
- 安装 Caddy 并配置自动 HTTPS
- 编译 / 部署 Rust 二进制
- 初始化 SQLite 数据库与管理员账号
- 注册 systemd 服务并自启
- 防火墙加固，仅允许 443 访问面板
 
5. 等待编译完成
 
- 1核2G VPS：首次  --release  编译约 8–15 分钟
- 2核4G VPS：约 4–7 分钟
- 本地已编译好二进制并上传：秒级完成
 
看到绿色提示  部署完成  即成功。
 
三、访问面板
 
浏览器打开：
 
plaintext
  
https://你的域名
 
 
使用步骤4中设置的 管理员账号/密码 登录。
 
四、常用服务管理命令
 
1. 查看面板状态
 
bash
  
systemctl status realm-web
 
 
2. 重启/停止/启动
 
bash
  
systemctl restart realm-web
systemctl stop realm-web
systemctl start realm-web
 
 
3. 实时运行日志
 
bash
  
journalctl -u realm-web -f
 
 
4. Caddy 日志（HTTPS、反向代理）
 
bash
  
journalctl -u caddy -f
 
 
五、如果你是【本地预编译二进制】部署（推荐，最快）
 
1. 本地机器安装 Rust 环境
2. 进入项目  rust/  目录编译 release 版：
 
bash
  
cd rust
cargo build --release
 
 
3. 找到编译产物：
 
plaintext
  
rust/target/release/realm-web-rust
 
 
4. 上传到服务器项目目录下：
 
plaintext
  
/root/realm-web-deploy/rust/realm-web-rust
 
 
5. 再执行  ./deploy.sh ，脚本会直接使用该二进制，不在服务器编译，瞬间完成。
 
六、常见异常快速排查
 
1. 域名打不开
- 确认域名 A 记录指向服务器公网 IP
- 安全组/防火墙放通 80、443 端口
2. 服务启动失败
bash
  
journalctl -u realm-web -f
 
3. 提示缺少 sqlite 相关依赖
 
bash
  
apt update && apt install -y libsqlite3-dev
 
 
4. 端口 5000 无法直接访问
- 正常，脚本做了防火墙限制，只能通过 https 域名访问
 
七、极简版速记（适合老手）
 
bash
  
sudo -i
cd realm-web-deploy
chmod +x deploy.sh
./deploy.sh
# 填端口、账号、密码、域名
# 完成 → https://域名 
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
