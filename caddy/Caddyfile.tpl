# {{DOMAIN}} 由install.sh自动替换为用户输入的域名（main.sh传递）
{{DOMAIN}} {
    # 反向代理到Realm Web面板本地端口（自动适配main.sh设置的PORT）
    reverse_proxy 127.0.0.1:{{PORT}}

    # Caddy v2.10+ 标准自动HTTPS配置（自动申请/续期Let's Encrypt证书）
    tls

    # 优化代理请求头：解决真实IP、跨域、协议传递问题
    header {
        X-Real-IP {remote_host}
        X-Forwarded-For {remote_host}
        X-Forwarded-Proto {scheme}
        Host {host}
        # 增强HTTPS安全配置，强制HTTPS访问
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
    }

    # 开启gzip压缩，提升面板访问速度
    encode gzip

    # 限制请求体大小，防止恶意大请求攻击
    request_body_limit 10M
}
