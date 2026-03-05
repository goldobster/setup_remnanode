#!/usr/bin/env bash
#
# setup-nginx-xray.sh
# =============================
# Устанавливает и настраивает:
#   - nginx (слушает на 127.0.0.1:844 для Xray Reality target)
#   - acme.sh + TLS-сертификаты через Cloudflare DNS challenge
#   - Кастомный фейковый сайт (camouflage) для Reality
#   - grpc_pass проксирование xhttp трафика (опционально, для CDN)
#
# Предполагается:
#   - Ubuntu 22.04 / 24.04
#   - Xray / rw-core уже установлен (например, через Remnawave)
#   - Домен на Cloudflare (DNS challenge)
#
# Использование:
#   chmod +x setup-nginx-xray.sh
#
#   # Интерактивный режим (как раньше):
#   sudo ./setup-nginx-xray.sh
#
#   # Неинтерактивный режим (все параметры через опции):
#   sudo ./setup-nginx-xray.sh \
#     -d proxy.example.com \
#     -t "CF_API_TOKEN_HERE" \
#     -e "admin@example.com" \
#     -p "/aB3x9kL2mNp" \
#     -y
#

set -euo pipefail

# ==================== ЦВЕТА ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}━━━ $* ━━━${NC}\n"; }

# ==================== USAGE ====================
usage() {
    cat << 'EOF'
Использование: setup-nginx-xray.sh [ОПЦИИ]

Опции:
  -d, --domain ДОМЕН          Домен для Reality (например, proxy.example.com)
  -t, --cf-token ТОКЕН        Cloudflare API Token (Zone:DNS:Edit)
  -e, --email EMAIL           Email для Let's Encrypt (опционально)
  -p, --path ПУТЬ             xhttp path (по умолчанию: /aB3x9kL2mNp)
  -l, --listen АДРЕС          Адрес nginx (по умолчанию: 127.0.0.1:844)
  -y, --yes                   Пропустить подтверждение (автоматический режим)
  -h, --help                  Показать эту справку

Примеры:
  # Полностью неинтерактивный запуск:
  sudo ./setup-nginx-xray.sh -d proxy.example.com -t "cf_token" -e "me@mail.com" -y

  # Минимальный набор (остальное — по умолчанию):
  sudo ./setup-nginx-xray.sh -d proxy.example.com -t "cf_token" -y

  # Интерактивный режим (без опций):
  sudo ./setup-nginx-xray.sh
EOF
    exit 0
}

# ==================== ПРОВЕРКИ ====================
if [[ $EUID -ne 0 ]]; then
    log_error "Запусти скрипт от root: sudo ./setup-nginx-xray.sh"
    exit 1
fi

if ! grep -qiE 'ubuntu' /etc/os-release 2>/dev/null; then
    log_warn "Скрипт тестировался на Ubuntu 22.04/24.04. На другой ОС могут быть проблемы."
fi

# ==================== ПАРСИНГ АРГУМЕНТОВ ====================
DOMAIN=""
CF_TOKEN=""
ACME_EMAIL=""
XHTTP_PATH="/aB3x9kL2mNp"
NGINX_LISTEN_ADDR="127.0.0.1:844"
AUTO_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -t|--cf-token)
            CF_TOKEN="$2"
            shift 2
            ;;
        -e|--email)
            ACME_EMAIL="$2"
            shift 2
            ;;
        -p|--path)
            XHTTP_PATH="$2"
            shift 2
            ;;
        -l|--listen)
            NGINX_LISTEN_ADDR="$2"
            shift 2
            ;;
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            log_error "Неизвестная опция: $1"
            echo ""
            usage
            ;;
        *)
            log_error "Неожиданный аргумент: $1"
            echo ""
            usage
            ;;
    esac
done

# ==================== ИНТЕРАКТИВНЫЙ ВВОД (если не задано через опции) ====================
log_step "Конфигурация"

if [[ -z "$DOMAIN" ]]; then
    read -rp "Введи домен для Reality (например, proxy.example.com): " DOMAIN
fi
if [[ -z "$DOMAIN" ]]; then
    log_error "Домен не может быть пустым. Используй: -d proxy.example.com"
    exit 1
fi

if [[ -z "$CF_TOKEN" ]]; then
    echo ""
    echo "Для DNS challenge нужен Cloudflare API Token."
    echo "Создай его: Cloudflare Dashboard → My Profile → API Tokens → Create Token"
    echo "Нужны права: Zone:DNS:Edit для нужной зоны."
    echo ""
    read -rp "Cloudflare API Token: " CF_TOKEN
fi
if [[ -z "$CF_TOKEN" ]]; then
    log_error "API Token не может быть пустым. Используй: -t \"TOKEN\""
    exit 1
fi

if [[ -z "$ACME_EMAIL" ]] && [[ "$AUTO_CONFIRM" == false ]]; then
    read -rp "Email для Let's Encrypt (опционально, Enter для пропуска): " ACME_EMAIL
fi

if [[ "$XHTTP_PATH" == "/aB3x9kL2mNp" ]] && [[ "$AUTO_CONFIRM" == false ]]; then
    echo ""
    echo "Укажи path для xhttp (должен совпадать с конфигом Xray)."
    echo "Используй что-то сложное, например: /aB3x9kL2mNp"
    read -rp "xhttp path [/aB3x9kL2mNp]: " INPUT_PATH
    XHTTP_PATH="${INPUT_PATH:-$XHTTP_PATH}"
fi

CERT_DIR="/etc/ssl/xray/${DOMAIN}"
WEBSITE_DIR="/var/www/camouflage"
NGINX_CONF="/etc/nginx/nginx.conf"
XRAY_EXAMPLE_CONF="/etc/xray/config.example.json"

echo ""
log_info "Домен:            ${DOMAIN}"
log_info "xhttp path:       ${XHTTP_PATH}"
log_info "Сертификаты:      ${CERT_DIR}"
log_info "Фейк-сайт:       ${WEBSITE_DIR}"
log_info "nginx слушает на: ${NGINX_LISTEN_ADDR}"
echo ""

if [[ "$AUTO_CONFIRM" == false ]]; then
    read -rp "Всё верно? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        log_warn "Отменено."
        exit 0
    fi
fi

# ==================== УСТАНОВКА ПАКЕТОВ ====================
log_step "1/6 — Установка пакетов"

apt-get update -qq
apt-get install -y -qq nginx curl socat cron git > /dev/null 2>&1
log_info "nginx $(nginx -v 2>&1 | cut -d'/' -f2) установлен"

systemctl stop nginx 2>/dev/null || true

# ==================== ЛИМИТ ОТКРЫТЫХ ФАЙЛОВ ====================
mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/override.conf << 'EOF'
[Service]
LimitNOFILE=65535
EOF
systemctl daemon-reload
log_info "Лимит открытых файлов для nginx: 65535"

# ==================== УСТАНОВКА ACME.SH ====================
log_step "2/6 — Установка acme.sh"

ACME_HOME="/root/.acme.sh"
ACME_SH="${ACME_HOME}/acme.sh"

if [[ ! -f "${ACME_SH}" ]]; then
    log_info "acme.sh не найден, устанавливаю..."

    TMPDIR_ACME="$(mktemp -d)"
    git clone --depth 1 https://github.com/acmesh-official/acme.sh.git "${TMPDIR_ACME}" 2>/dev/null

    cd "${TMPDIR_ACME}"
    ./acme.sh --install \
        --home "${ACME_HOME}" \
        ${ACME_EMAIL:+--accountemail "${ACME_EMAIL}"}
    cd /root
    rm -rf "${TMPDIR_ACME}"

    if [[ ! -f "${ACME_SH}" ]]; then
        log_error "acme.sh не удалось установить."
        exit 1
    fi
    log_info "acme.sh установлен: ${ACME_SH}"
else
    log_info "acme.sh уже установлен: ${ACME_SH}"
fi

if [[ -f "${ACME_HOME}/acme.sh.env" ]]; then
    source "${ACME_HOME}/acme.sh.env"
fi

# ==================== ВЫПУСК СЕРТИФИКАТА ====================
log_step "3/6 — Выпуск TLS-сертификата"

mkdir -p "${CERT_DIR}"

export CF_Token="${CF_TOKEN}"

if [[ -f "${CERT_DIR}/fullchain.crt" && -f "${CERT_DIR}/private.key" ]]; then
    log_info "Сертификаты уже существуют в ${CERT_DIR}, пропускаем выпуск"
    log_info "Для перевыпуска удали ${CERT_DIR} и запусти скрипт снова"
else
    log_info "Запрашиваю сертификат для ${DOMAIN}..."

    "${ACME_SH}" --issue \
        --dns dns_cf \
        -d "${DOMAIN}" \
        --keylength ec-256 \
        --server letsencrypt \
        --force

    "${ACME_SH}" --install-cert -d "${DOMAIN}" --ecc \
        --cert-file      "${CERT_DIR}/cert.crt" \
        --key-file       "${CERT_DIR}/private.key" \
        --fullchain-file "${CERT_DIR}/fullchain.crt" \
        --ca-file        "${CERT_DIR}/ca.crt" \
        --reloadcmd      "systemctl reload nginx 2>/dev/null || true"

    log_info "Сертификат выпущен и установлен в ${CERT_DIR}"
fi

chmod 644 "${CERT_DIR}"/*.crt 2>/dev/null || true
chmod 600 "${CERT_DIR}/private.key"

# ==================== ФЕЙКОВЫЙ САЙТ ====================
log_step "4/6 — Создание фейкового сайта"

mkdir -p "${WEBSITE_DIR}"

if [[ ! -f "${WEBSITE_DIR}/index.html" ]]; then
cat > "${WEBSITE_DIR}/index.html" << 'SITEHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f5f5f5; color: #333;
            min-height: 100vh; display: flex; flex-direction: column;
        }
        header { background: #fff; border-bottom: 1px solid #e0e0e0; padding: 20px 40px; }
        header h1 { font-size: 1.4rem; font-weight: 600; color: #1a1a1a; }
        main { flex: 1; max-width: 800px; margin: 40px auto; padding: 0 20px; }
        .card {
            background: #fff; border-radius: 8px; padding: 32px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.08); margin-bottom: 24px;
        }
        .card h2 { font-size: 1.2rem; margin-bottom: 12px; color: #1a1a1a; }
        .card p { line-height: 1.7; color: #555; }
        .features {
            display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 16px; margin-top: 16px;
        }
        .feature { background: #f9f9f9; border-radius: 6px; padding: 16px; }
        .feature h3 { font-size: 0.95rem; margin-bottom: 6px; color: #1a1a1a; }
        .feature p { font-size: 0.85rem; color: #777; }
        footer { text-align: center; padding: 20px; color: #999; font-size: 0.8rem; }
    </style>
</head>
<body>
    <header><h1>TechNova Solutions</h1></header>
    <main>
        <div class="card">
            <h2>Cloud Infrastructure &amp; DevOps</h2>
            <p>We provide modern cloud solutions for businesses of all sizes.
               Our team specializes in building reliable, scalable infrastructure
               that grows with your needs.</p>
        </div>
        <div class="card">
            <h2>Our Services</h2>
            <div class="features">
                <div class="feature"><h3>Cloud Migration</h3><p>Seamless transition to cloud-native architecture.</p></div>
                <div class="feature"><h3>CI/CD Pipelines</h3><p>Automated deployment workflows for faster delivery.</p></div>
                <div class="feature"><h3>Monitoring</h3><p>24/7 infrastructure monitoring and alerting.</p></div>
                <div class="feature"><h3>Security Audit</h3><p>Comprehensive security assessment and hardening.</p></div>
            </div>
        </div>
        <div class="card">
            <h2>Contact</h2>
            <p>Get in touch with our team to discuss your project requirements.</p>
        </div>
    </main>
    <footer>&copy; 2025 TechNova Solutions. All rights reserved.</footer>
</body>
</html>
SITEHTML
    log_info "Шаблонная страница создана: ${WEBSITE_DIR}/index.html"
    log_info "Замени её на свою: scp your-site/* root@server:${WEBSITE_DIR}/"
else
    log_info "Фейковый сайт уже существует, не перезаписываю"
fi

# ==================== КОНФИГУРАЦИЯ NGINX ====================
log_step "5/6 — Конфигурация nginx"

if [[ -f "${NGINX_CONF}" ]]; then
    cp "${NGINX_CONF}" "${NGINX_CONF}.bak.$(date +%s)"
fi

# Определяем версию nginx для совместимости директив
NGINX_VER_FULL=$(nginx -v 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)
NGINX_MINOR=$(echo "${NGINX_VER_FULL}" | cut -d. -f2)
NGINX_PATCH=$(echo "${NGINX_VER_FULL}" | cut -d. -f3)
log_info "nginx версия: ${NGINX_VER_FULL}"

# http2_max_concurrent_streams: deprecated в nginx >= 1.25.0
H2_STREAMS=""
if [[ "${NGINX_MINOR}" -lt 25 ]]; then
    H2_STREAMS="        http2_max_concurrent_streams 1024;"
fi

# keepalive_time: появилась в nginx 1.19.10
KEEPALIVE_TIME=""
if [[ "${NGINX_MINOR}" -gt 19 ]] || { [[ "${NGINX_MINOR}" -eq 19 ]] && [[ "${NGINX_PATCH}" -ge 10 ]]; }; then
    KEEPALIVE_TIME="        keepalive_time               2h;"
fi

cat > "${NGINX_CONF}" << 'NGINXEOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 2048;
    multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    set_real_ip_from    127.0.0.1;
    real_ip_header      X-Forwarded-For;
    real_ip_recursive   on;

    log_format custom '$remote_addr [$time_iso8601] "$request_method $ssl_server_name'
                      '$uri $server_protocol" $status $body_bytes_sent'
                      'B "$host" "$http_user_agent" $request_time'
                      'ms';
    access_log  off;
    log_not_found off;

    sendfile              on;
    server_tokens         off;
    tcp_nodelay           on;
    tcp_nopush            on;
    client_max_body_size  0;
    gzip                  on;
    gzip_types            text/plain text/css application/json application/javascript text/xml;

    add_header X-Content-Type-Options nosniff;

    ssl_session_cache          shared:SSL:16m;
    ssl_session_timeout        1h;
    ssl_session_tickets        off;
    ssl_protocols              TLSv1.3 TLSv1.2;
    ssl_ciphers                TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers  on;

    # ssl_stapling отключён: Let's Encrypt убрал OCSP из сертификатов в 2025
    ssl_stapling               off;
    ssl_stapling_verify        off;

    resolver                   1.1.1.1 8.8.8.8 valid=60s;
    resolver_timeout           2s;

    map $remote_addr $proxy_forwarded_elem {
        ~^[0-9.]+$        "for=$remote_addr";
        ~^[0-9A-Fa-f:.]+$ "for=\"[$remote_addr]\"";
        default           "for=unknown";
    }

    map $http_forwarded $proxy_add_forwarded {
        "~^(,[ \\t]*)*([!#$%&'*+.^_`|~0-9A-Za-z-]+=([!#$%&'*+.^_`|~0-9A-Za-z-]+|\"([\\t \\x21\\x23-\\x5B\\x5D-\\x7E\\x80-\\xFF]|\\\\[\\t \\x21-\\x7E\\x80-\\xFF])*\"))?(;([!#$%&'*+.^_`|~0-9A-Za-z-]+=([!#$%&'*+.^_`|~0-9A-Za-z-]+|\"([\\t \\x21\\x23-\\x5B\\x5D-\\x7E\\x80-\\xFF]|\\\\[\\t \\x21-\\x7E\\x80-\\xFF])*\"))?)*([ \\t]*,([ \\t]*([!#$%&'*+.^_`|~0-9A-Za-z-]+=([!#$%&'*+.^_`|~0-9A-Za-z-]+|\"([\\t \\x21\\x23-\\x5B\\x5D-\\x7E\\x80-\\xFF]|\\\\[\\t \\x21-\\x7E\\x80-\\xFF])*\"))?(;([!#$%&'*+.^_`|~0-9A-Za-z-]+=([!#$%&'*+.^_`|~0-9A-Za-z-]+|\"([\\t \\x21\\x23-\\x5B\\x5D-\\x7E\\x80-\\xFF]|\\\\[\\t \\x21-\\x7E\\x80-\\xFF])*\"))?)*)?)*$" "$http_forwarded, $proxy_forwarded_elem";
        default "$proxy_forwarded_elem";
    }

    # ═══════════════════════════════════════════════════════════
    # Reality target — фейковый сайт + xhttp проксирование
    # ═══════════════════════════════════════════════════════════
    server {
        listen       __NGINX_LISTEN_ADDR__ ssl http2 backlog=2048 so_keepalive=on;
        server_name  __DOMAIN__;

        ssl_certificate            __CERT_DIR__/fullchain.crt;
        ssl_certificate_key        __CERT_DIR__/private.key;
        ssl_trusted_certificate    __CERT_DIR__/ca.crt;

        # access_log /var/log/nginx/access_xray.log custom buffer=16k flush=5s;
        error_log  /var/log/nginx/error_xray.log error;

__H2_STREAMS__
__KEEPALIVE_TIME__
        keepalive_timeout            600s;
        keepalive_requests           2048;
        client_body_buffer_size      1m;
        client_body_timeout          600s;
        client_header_timeout        300s;
        large_client_header_buffers  8 16k;
        proxy_connect_timeout        30s;
        proxy_read_timeout           2h;
        proxy_send_timeout           2h;
        proxy_buffering              off;
        proxy_request_buffering      off;

        location / {
            root __WEBSITE_DIR__;
            index index.html;
        }

        # xhttp проксирование через grpc_pass (для CDN, на будущее)
        location __XHTTP_PATH__ {
            grpc_buffer_size         16k;
            grpc_socket_keepalive    on;
            grpc_read_timeout        1h;
            grpc_send_timeout        1h;

            grpc_set_header Connection         "";
            grpc_set_header X-Real-IP          $remote_addr;
            grpc_set_header Forwarded          $proxy_add_forwarded;
            grpc_set_header X-Forwarded-For    $proxy_add_x_forwarded_for;
            grpc_set_header X-Forwarded-Proto  $scheme;
            grpc_set_header X-Forwarded-Port   $server_port;
            grpc_set_header Host               $host;
            grpc_set_header X-Forwarded-Host   $host;

            grpc_pass unix:/dev/shm/xhttp_client_upload.sock;
        }
    }

    # HTTP → HTTPS редирект
    server {
        listen       80 default_server;
        listen       [::]:80 default_server;
        server_name  __DOMAIN__;
        return 301   https://$host$request_uri;
    }
}
NGINXEOF

sed -i \
    -e "s|__DOMAIN__|${DOMAIN}|g" \
    -e "s|__CERT_DIR__|${CERT_DIR}|g" \
    -e "s|__WEBSITE_DIR__|${WEBSITE_DIR}|g" \
    -e "s|__XHTTP_PATH__|${XHTTP_PATH}|g" \
    -e "s|__NGINX_LISTEN_ADDR__|${NGINX_LISTEN_ADDR}|g" \
    -e "s|__H2_STREAMS__|${H2_STREAMS}|g" \
    -e "s|__KEEPALIVE_TIME__|${KEEPALIVE_TIME}|g" \
    "${NGINX_CONF}"

log_info "Конфиг nginx создан: ${NGINX_CONF}"

set +e
nginx -t 2>&1
NGINX_TEST=$?
set -e

if [[ $NGINX_TEST -eq 0 ]]; then
    log_info "nginx -t: конфиг валиден"
else
    log_error "nginx -t: ошибка в конфиге! Проверь ${NGINX_CONF}"
    exit 1
fi

# ==================== ПРИМЕР КОНФИГА XRAY ====================
log_step "6/6 — Генерация примера конфига Xray"

mkdir -p "$(dirname "${XRAY_EXAMPLE_CONF}")"

cat > "${XRAY_EXAMPLE_CONF}" << 'XRAYEOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "REPLACE_WITH_UUID_VISION",
            "level": 0,
            "email": "vision-user",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": "/dev/shm/xhttp_client_upload.sock",
            "xver": 0
          }
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "__NGINX_LISTEN_ADDR__",
          "xver": 0,
          "serverNames": [
            "__DOMAIN__"
          ],
          "privateKey": "REPLACE_WITH_PRIVATE_KEY",
          "shortIds": ["REPLACE_WITH_SHORT_ID"]
        },
        "sockopt": {
          "tcpFastOpen": true,
          "tcpcongestion": "bbr",
          "tcpMptcp": true,
          "tcpNoDelay": true
        }
      },
      "tag": "VISION+REALITY",
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false,
        "routeOnly": true
      }
    },
    {
      "listen": "/dev/shm/xhttp_client_upload.sock,0666",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "REPLACE_WITH_UUID_XHTTP",
            "level": 0,
            "email": "xhttp-user"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "host": "",
          "path": "__XHTTP_PATH__",
          "mode": "auto",
          "extra": {
            "noSSEHeader": false,
            "scMaxEachPostBytes": 1000000,
            "scMaxBufferedPosts": 30,
            "xPaddingBytes": "100-1000"
          }
        },
        "sockopt": {
          "tcpFastOpen": true,
          "acceptProxyProtocol": false,
          "tcpcongestion": "bbr",
          "tcpMptcp": true,
          "tcpNoDelay": true
        }
      },
      "tag": "XHTTP_IN",
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false,
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
XRAYEOF

sed -i \
    -e "s|__DOMAIN__|${DOMAIN}|g" \
    -e "s|__XHTTP_PATH__|${XHTTP_PATH}|g" \
    -e "s|__NGINX_LISTEN_ADDR__|${NGINX_LISTEN_ADDR}|g" \
    "${XRAY_EXAMPLE_CONF}"

log_info "Пример конфига Xray: ${XRAY_EXAMPLE_CONF}"
log_info "Замени плейсхолдеры REPLACE_WITH_* на свои значения:"
log_info "  xray x25519         — генерация ключевой пары"
log_info "  xray uuid           — генерация UUID"
log_info "  openssl rand -hex 8 — генерация shortId"

# ==================== ЗАПУСК ====================
log_step "Запуск nginx"

systemctl enable nginx
systemctl start nginx
log_info "nginx запущен"

# ==================== ИТОГ ====================
log_step "Готово!"

cat << EOF

  Установка завершена
  ───────────────────
  Домен:            ${DOMAIN}
  Сертификаты:      ${CERT_DIR}/
  Фейк-сайт:       ${WEBSITE_DIR}/
  nginx конфиг:     ${NGINX_CONF}
  nginx слушает на: ${NGINX_LISTEN_ADDR}
  Xray пример:      ${XRAY_EXAMPLE_CONF}
  xhttp path:       ${XHTTP_PATH}

  Следующие шаги:

  1. В панели Remnawave (или конфиге Xray):
     Reality target → "${NGINX_LISTEN_ADDR}"

  2. Замени фейковый сайт на свой:
     scp -r ./my-site/* root@server:${WEBSITE_DIR}/
     systemctl reload nginx

  3. Проверь:
     systemctl status nginx
     curl -k https://127.0.0.1:844/

  ВАЖНО: Xray/rw-core слушает порт 443 и направляет Reality target
  на ${NGINX_LISTEN_ADDR} (nginx). Nginx не доступен извне — только
  через Xray. Весь TLS обрабатывается Xray через Reality.

EOF
