{{DOMAIN}} {
    # 反向代理到面板本地端口
    reverse_proxy 127.0.0.1:5000
    # 自动HTTPS（Caddy2.10+标准配置）
    tls
    # 真实IP/跨域/安全头配置
    header {
        X-Real-IP {remote_host}
        X-Forwarded-For {remote_host}
        X-Forwarded-Proto {scheme}
        Host {host}
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
    }
    # 开启gzip压缩
    encode gzip
    # 限制请求体大小
    request_body_limit 10M
}
