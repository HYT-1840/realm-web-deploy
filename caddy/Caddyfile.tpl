{{DOMAIN}} {
    reverse_proxy 127.0.0.1:5000
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
