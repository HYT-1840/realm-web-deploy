# {{DOMAIN}} 是部署时的变量，脚本会自动替换为用户输入的域名
{{DOMAIN}} {
    # 反向代理到Realm Web面板本地端口5000
    reverse_proxy 127.0.0.1:5000

    # Caddy自动申请Let's Encrypt SSL证书（自动续期，零操作）
    tls {
        renew_before 30d
        storage /var/lib/caddy/.local/share/caddy/certificates
    }

    # 优化代理请求头，解决面板真实IP、跨域问题
    header {
        X-Real-IP {remote_host}
        X-Forwarded-For {remote_host}
        X-Forwarded-Proto {scheme}
        Host {host}
        # 增强HTTPS安全配置
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
    }

    # 开启gzip压缩，提升访问速度
    encode gzip

    # 限制请求体大小，防止恶意请求
    request_body_limit 10M
}
