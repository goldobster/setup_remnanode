#!/bin/bash

set -e

# ==============================
# RemnaNode Auto-Setup Script
# ==============================
# Автоматическая установка и настройка RemnaNode
# через API Remnawave Panel
# ==============================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Значения по умолчанию ──
PANEL_URL=""
API_TOKEN=""
NODE_NAME=""
NODE_PORT=2222
SECRET_KEY=""
SERVER_IP=""

# ── Справка ──
usage() {
    echo ""
    echo "============================================"
    echo "   RemnaNode — Автоматическая установка"
    echo "============================================"
    echo ""
    echo "Использование:"
    echo "  sudo $0 [опции]"
    echo ""
    echo "Опции:"
    echo "  --panel-url URL       URL панели Remnawave (например, https://panel.example.com)"
    echo "  --api-token TOKEN     API-токен для авторизации в панели"
    echo "  --node-name NAME      Имя ноды (например, Node-DE-1)"
    echo "  --node-port PORT      Порт ноды (по умолчанию: 2222)"
    echo "  --secret-key KEY      SECRET_KEY (если не указан — генерируется через API keygen)"
    echo "  --server-ip IP        Внешний IP-адрес сервера (если не указан — определяется автоматически)"
    echo "  --help, -h            Показать эту справку"
    echo "  --info                Показать описание всех опций с примерами"
    echo ""
    echo "Примеры:"
    echo "  # Полностью автоматическая установка:"
    echo "  sudo $0 --panel-url https://panel.example.com --api-token mytoken123 --node-name Node-DE-1"
    echo ""
    echo "  # С указанием всех параметров:"
    echo "  sudo $0 --panel-url https://panel.example.com --api-token mytoken123 \\"
    echo "          --node-name Node-DE-1 --node-port 3333 --server-ip 1.2.3.4"
    echo ""
    echo "  # Без опций — скрипт запросит данные интерактивно:"
    echo "  sudo $0"
    echo ""
    exit 0
}

show_info() {
    echo ""
    echo "============================================"
    echo "   RemnaNode — Описание опций"
    echo "============================================"
    echo ""
    echo -e "${CYAN}--panel-url${NC} (обязательный)"
    echo "  URL вашей панели Remnawave, включая протокол (https://)."
    echo "  Завершающий слэш будет удалён автоматически."
    echo "  Пример: --panel-url https://panel.example.com"
    echo ""
    echo -e "${CYAN}--api-token${NC} (обязательный)"
    echo "  Токен авторизации для работы с API панели."
    echo "  Получить можно в настройках панели Remnawave."
    echo "  Пример: --api-token eyJhbGciOiJIUzI1NiIs..."
    echo ""
    echo -e "${CYAN}--node-name${NC} (обязательный)"
    echo "  Человекочитаемое имя ноды, которое будет отображаться в панели."
    echo "  Пример: --node-name Node-DE-1"
    echo ""
    echo -e "${CYAN}--node-port${NC} (необязательный, по умолчанию: 2222)"
    echo "  Порт, на котором будет работать нода."
    echo "  Пример: --node-port 3333"
    echo ""
    echo -e "${CYAN}--secret-key${NC} (необязательный)"
    echo "  Ключ шифрования для ноды. Если не указан, будет"
    echo "  сгенерирован автоматически через API keygen панели."
    echo "  Пример: --secret-key your_secret_key_here"
    echo ""
    echo -e "${CYAN}--server-ip${NC} (необязательный)"
    echo "  Внешний IP-адрес сервера. Если не указан, будет"
    echo "  определён автоматически через внешние сервисы."
    echo "  Пример: --server-ip 203.0.113.42"
    echo ""
    exit 0
}

# ── Парсинг аргументов ──
while [[ $# -gt 0 ]]; do
    case "$1" in
        --panel-url)
            PANEL_URL="${2%/}"
            shift 2
            ;;
        --api-token)
            API_TOKEN="$2"
            shift 2
            ;;
        --node-name)
            NODE_NAME="$2"
            shift 2
            ;;
        --node-port)
            NODE_PORT="$2"
            shift 2
            ;;
        --secret-key)
            SECRET_KEY="$2"
            shift 2
            ;;
        --server-ip)
            SERVER_IP="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        --info)
            show_info
            ;;
        *)
            error "Неизвестная опция: $1\nИспользуйте --help для просмотра доступных опций."
            ;;
    esac
done

# ── Проверка root ──
if [[ $EUID -ne 0 ]]; then
    error "Скрипт необходимо запускать от root (sudo)."
fi

echo ""
echo "============================================"
echo "   RemnaNode — Автоматическая установка"
echo "============================================"
echo ""

# ── Интерактивный ввод недостающих данных ──
if [[ -z "$PANEL_URL" ]]; then
    read -rp "Введите URL панели Remnawave (например, https://panel.example.com): " PANEL_URL
    PANEL_URL="${PANEL_URL%/}"
fi
[[ -z "$PANEL_URL" ]] && error "URL панели не может быть пустым."

if [[ -z "$API_TOKEN" ]]; then
    read -rp "Введите API-токен Remnawave: " API_TOKEN
fi
[[ -z "$API_TOKEN" ]] && error "API-токен не может быть пустым."

if [[ -z "$NODE_NAME" ]]; then
    read -rp "Введите имя ноды (например, Node-DE-1): " NODE_NAME
fi
[[ -z "$NODE_NAME" ]] && error "Имя ноды не может быть пустым."

# ── Показ конфигурации ──
echo ""
info "Конфигурация:"
echo "  Panel URL:   ${PANEL_URL}"
echo "  Node Name:   ${NODE_NAME}"
echo "  Node Port:   ${NODE_PORT}"
[[ -n "$SECRET_KEY" ]] && echo "  Secret Key:  (указан вручную)" || echo "  Secret Key:  (будет сгенерирован)"
[[ -n "$SERVER_IP" ]]  && echo "  Server IP:   ${SERVER_IP}" || echo "  Server IP:   (будет определён автоматически)"
echo ""

# ── 1. Обновление системы ──
info "Обновление списка пакетов и апгрейд системы..."
apt update -y && apt upgrade -y
ok "Система обновлена."

# ── 2. Установка Docker и Docker Compose ──
if command -v docker &>/dev/null; then
    ok "Docker уже установлен: $(docker --version)"
else
    info "Установка Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    ok "Docker установлен: $(docker --version)"
fi

if docker compose version &>/dev/null; then
    ok "Docker Compose доступен: $(docker compose version --short)"
else
    error "Docker Compose (plugin) не найден. Убедитесь, что Docker установлен корректно."
fi

# ── 3. Проверка подключения к API ──
info "Проверка подключения к панели..."

AUTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${PANEL_URL}/api/auth/status")

if [[ "$AUTH_CHECK" != "200" ]]; then
    error "Не удалось подключиться к панели (HTTP ${AUTH_CHECK}). Проверьте URL и API-токен."
fi
ok "Подключение к панели успешно."

# ── 4. Получение SECRET_KEY через API keygen (если не указан) ──
if [[ -z "$SECRET_KEY" ]]; then
    info "Генерация ключа для ноды через API (keygen)..."

    KEYGEN_RESPONSE=$(curl -s \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${PANEL_URL}/api/keygen")

    SECRET_KEY=$(echo "$KEYGEN_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    resp = data.get('response', data)
    if isinstance(resp, dict):
        print(resp.get('pubKey', resp.get('pubkey', resp.get('key', ''))))
    elif isinstance(resp, str):
        print(resp)
    else:
        print('')
except:
    print('')
" 2>/dev/null)

    if [[ -z "$SECRET_KEY" ]]; then
        echo ""
        warn "Не удалось автоматически извлечь ключ из ответа API."
        echo "Ответ API:"
        echo "$KEYGEN_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$KEYGEN_RESPONSE"
        echo ""
        read -rp "Введите SECRET_KEY вручную: " SECRET_KEY
        if [[ -z "$SECRET_KEY" ]]; then
            error "SECRET_KEY не может быть пустым."
        fi
    fi
fi

ok "SECRET_KEY получен."

# ── 5. Создание директории и docker-compose.yml ──
info "Создание /opt/remnanode и docker-compose.yml..."

mkdir -p /opt/remnanode
cat > /opt/remnanode/docker-compose.yml <<EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY="${SECRET_KEY}"
EOF

ok "docker-compose.yml создан в /opt/remnanode/"

# ── 6. Запуск контейнера ──
info "Запуск контейнера remnanode..."

cd /opt/remnanode
docker compose pull
docker compose up -d

sleep 5

if docker ps --format '{{.Names}}' | grep -q "remnanode"; then
    ok "Контейнер remnanode запущен."
else
    warn "Контейнер может ещё запускаться. Проверьте: docker ps"
fi

# ── 7. Определение IP-адреса сервера (если не указан) ──
if [[ -z "$SERVER_IP" ]]; then
    info "Определение внешнего IP-адреса..."

    SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || \
                curl -s -4 icanhazip.com 2>/dev/null || \
                curl -s -4 ipinfo.io/ip 2>/dev/null || \
                hostname -I | awk '{print $1}')

    if [[ -z "$SERVER_IP" ]]; then
        read -rp "Не удалось определить IP. Введите IP-адрес сервера вручную: " SERVER_IP
    fi
fi

ok "IP-адрес сервера: ${SERVER_IP}"

# ── 8. Получение Config Profile ──
info "Получение списка Config Profiles..."

CONFIG_PROFILES_RESPONSE=$(curl -s \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${PANEL_URL}/api/config-profiles")

CONFIG_DATA=$(echo "$CONFIG_PROFILES_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    resp = data.get('response', data)
    profiles = resp.get('configProfiles', [])
    if profiles:
        profile = profiles[0]
        uuid = profile.get('uuid', '')
        inbounds = profile.get('inbounds', [])
        inbound_uuids = [ib.get('uuid') for ib in inbounds if isinstance(ib, dict) and ib.get('uuid')]
        print(json.dumps({'uuid': uuid, 'inbounds': inbound_uuids}))
    else:
        print(json.dumps({'uuid': '', 'inbounds': []}))
except:
    print(json.dumps({'uuid': '', 'inbounds': []}))
" 2>/dev/null)

CONFIG_PROFILE_UUID=$(echo "$CONFIG_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['uuid'])" 2>/dev/null || echo "")
INBOUND_UUIDS_JSON=$(echo "$CONFIG_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d['inbounds']))" 2>/dev/null || echo '[]')

if [[ -n "$CONFIG_PROFILE_UUID" && "$CONFIG_PROFILE_UUID" != "" ]]; then
    ok "Config Profile найден: ${CONFIG_PROFILE_UUID}"
else
    error "Config Profile не найден. Создайте профиль в панели и запустите скрипт заново."
fi

# ── 9. Создание ноды через API ──
info "Создание ноды '${NODE_NAME}' в панели..."

CREATE_NODE_BODY=$(python3 -c "
import json
body = {
    'name': '${NODE_NAME}',
    'address': '${SERVER_IP}',
    'port': ${NODE_PORT},
    'configProfile': {
        'activeConfigProfileUuid': '${CONFIG_PROFILE_UUID}',
        'activeInbounds': ${INBOUND_UUIDS_JSON}
    }
}
print(json.dumps(body))
" 2>/dev/null)

CREATE_NODE_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${CREATE_NODE_BODY}" \
    "${PANEL_URL}/api/nodes")

HTTP_CODE=$(echo "$CREATE_NODE_RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$CREATE_NODE_RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    ok "Нода успешно создана в панели!"

    NODE_UUID=$(echo "$RESPONSE_BODY" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    resp = data.get('response', data)
    print(resp.get('uuid', 'N/A'))
except:
    print('N/A')
" 2>/dev/null || echo "N/A")

    echo ""
    echo "============================================"
    echo -e "${GREEN}  Установка завершена успешно!${NC}"
    echo "============================================"
    echo ""
    echo "  Имя ноды:        ${NODE_NAME}"
    echo "  UUID ноды:       ${NODE_UUID}"
    echo "  IP-адрес:        ${SERVER_IP}"
    echo "  Порт:            ${NODE_PORT}"
    echo "  Config Profile:  ${CONFIG_PROFILE_UUID}"
    echo "  Директория:      /opt/remnanode"
    echo ""
    echo "  Полезные команды:"
    echo "    Логи:          cd /opt/remnanode && docker compose logs -f"
    echo "    Перезапуск:    cd /opt/remnanode && docker compose restart"
    echo "    Остановка:     cd /opt/remnanode && docker compose down"
    echo ""
else
    echo ""
    warn "Не удалось создать ноду в панели (HTTP ${HTTP_CODE})."
    echo "Ответ API:"
    echo "$RESPONSE_BODY" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE_BODY"
    echo ""
    echo "Контейнер remnanode запущен и работает."
    echo "Вы можете добавить ноду в панель вручную:"
    echo "  Адрес: ${SERVER_IP}"
    echo "  Порт:  ${NODE_PORT}"
    echo ""
fi
