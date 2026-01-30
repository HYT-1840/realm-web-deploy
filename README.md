# realm-web-deploy

realm-web-deploy/
├── app.py                # 后端核心（Flask+多用户鉴权+Realm进程管控）
├── deploy.sh             # Linux 自动部署脚本（交互式+详细日志）
├── README.md             # 项目说明+部署指南
└── templates/            # 前端页面目录
    ├── login.html        # 登录页（适配PC/移动端）
    └── index.html        # 主面板（多用户规则管理）
