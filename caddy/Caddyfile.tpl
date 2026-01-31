# {{DOMAIN}} 会被脚本自动替换为用户输入的域名
{{DOMAIN}} {
    reverse_proxy 127.0.0.1:5000

    # 最简合法tls配置，Caddy 2全版本通用，自动SSL+自动续期
    tls

    header {
        X-Real-IP {remote_host}
        X-Forwarded-For {remote_host}
        X-Forwarded-Proto {scheme}
        Host {host}
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
    }

    encode gzip
    request_body_limit 10M
}
