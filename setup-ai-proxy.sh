#!/bin/bash
set -e

# Проверка запуска от root
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31mОШИБКА: Этот скрипт должен быть запущен с правами root (sudo -i)\033[0m"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Проверяем и тихо доустанавливаем минимально необходимые системные утилиты
REQUIRED_PKGS=()
for cmd in curl jq python3 dig iptables ipset; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        case "$cmd" in
            dig) REQUIRED_PKGS+=("dnsutils") ;;
            *) REQUIRED_PKGS+=("$cmd") ;;
        esac
    fi
done

if [ ${#REQUIRED_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Доустанавливаем необходимые системные пакеты (${REQUIRED_PKGS[*]})...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y -qq "${REQUIRED_PKGS[@]}" >/dev/null 2>&1 || true
fi

# ==============================================================================
# ФУНКЦИЯ ДИАГНОСТИКИ НЕЙРОСЕТЕЙ (ПРОВЕРКА РЕГИОНА И СТРАН)
# ==============================================================================
test_ai_services() {
    local proxy="$1"
    echo ""
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${CYAN}        ТЕСТИРОВАНИЕ РЕГИОНА И ДОСТУПНОСТИ НЕЙРОСЕТЕЙ...${NC}"
    echo -e "${CYAN}====================================================================${NC}"

    # 1. IP info
    local ip_json
    ip_json=$(curl -x "$proxy" -m 7 -s "http://ip-api.com/json/?fields=country,countryCode,city,isp,query" 2>/dev/null || true)
    local ip country city isp
    ip=$(echo "$ip_json" | jq -r '.query // empty')
    country=$(echo "$ip_json" | jq -r '.country // empty')
    city=$(echo "$ip_json" | jq -r '.city // empty')
    isp=$(echo "$ip_json" | jq -r '.isp // empty')

    if [[ -z "$ip" ]]; then
        # Запасной запрос через ipify
        ip=$(curl -x "$proxy" -4 -m 5 -s https://api.ipify.org 2>/dev/null || true)
    fi

    if [[ -z "$ip" ]]; then
        echo -e "${RED}✗ ОШИБКА: Прокси не отвечает! Проверь IP, порт, логин и пароль.${NC}"
        return 1
    fi

    echo -e "Внешний IP:            ${GREEN}${BOLD}${ip}${NC} (${isp:-Unknown}, ${city:-}, ${country:-})"
    echo "--------------------------------------------------------------------"

    local has_blocked=false

    # 2. Google & Gemini
    local gl gemini_api gemini_status
    gl=$(curl -x "$proxy" -4 -m 7 -s https://www.youtube.com 2>/dev/null | grep -o '"GL":"[A-Z]*"' | head -n 1 | cut -d'"' -f4 || true)
    gemini_api=$(curl -x "$proxy" -m 7 -s "https://generativelanguage.googleapis.com/v1beta/models?key=test" 2>/dev/null || true)
    if echo "$gemini_api" | grep -q "User location is not supported"; then
        gemini_status="${RED}⛔ Заблокирован (${gl:-RU} — регион не поддерживается)${NC}"
        has_blocked=true
    elif echo "$gemini_api" | grep -q "API_KEY_INVALID"; then
        gemini_status="${GREEN}✓ Доступ открыт (${gl:-$country})${NC}"
    elif [[ -n "$gl" ]]; then
        gemini_status="${GREEN}✓ Регион Google: ${gl}${NC}"
    else
        gemini_status="${YELLOW}? Не удалось определить${NC}"
    fi
    printf "%-22s %b\n" "Google & Gemini:" "$gemini_status"

    # 3. OpenAI & ChatGPT
    local oai_trace oai_loc oai_colo oai_status
    oai_trace=$(curl -x "$proxy" -m 7 -s https://chatgpt.com/cdn-cgi/trace 2>/dev/null || true)
    oai_loc=$(echo "$oai_trace" | grep '^loc=' | cut -d'=' -f2)
    oai_colo=$(echo "$oai_trace" | grep '^colo=' | cut -d'=' -f2)
    if [[ "$oai_loc" == "RU" || "$oai_loc" == "BY" ]]; then
        oai_status="${RED}⛔ Заблокирован ($oai_loc)${NC}"
        has_blocked=true
    elif [[ -n "$oai_loc" ]]; then
        oai_status="${GREEN}✓ Доступ открыт ($oai_loc, ЦОД $oai_colo)${NC}"
    else
        oai_status="${YELLOW}? Не удалось определить${NC}"
    fi
    printf "%-22s %b\n" "OpenAI & ChatGPT:" "$oai_status"

    # 4. Anthropic Claude
    local claude_trace claude_loc claude_colo claude_status
    claude_trace=$(curl -x "$proxy" -m 7 -s https://claude.ai/cdn-cgi/trace 2>/dev/null || true)
    claude_loc=$(echo "$claude_trace" | grep '^loc=' | cut -d'=' -f2)
    claude_colo=$(echo "$claude_trace" | grep '^colo=' | cut -d'=' -f2)
    if [[ "$claude_loc" == "RU" || "$claude_loc" == "BY" ]]; then
        claude_status="${RED}⛔ Заблокирован ($claude_loc)${NC}"
        has_blocked=true
    elif [[ -n "$claude_loc" ]]; then
        claude_status="${GREEN}✓ Доступ открыт ($claude_loc, ЦОД $claude_colo)${NC}"
    else
        claude_status="${YELLOW}? Не удалось определить${NC}"
    fi
    printf "%-22s %b\n" "Anthropic Claude:" "$claude_status"

    # 5. Perplexity & Cursor
    local perp_trace perp_loc perp_status
    perp_trace=$(curl -x "$proxy" -m 7 -s https://www.perplexity.ai/cdn-cgi/trace 2>/dev/null || true)
    perp_loc=$(echo "$perp_trace" | grep '^loc=' | cut -d'=' -f2)
    if [[ "$perp_loc" == "RU" || "$perp_loc" == "BY" ]]; then
        perp_status="${RED}⛔ Заблокирован ($perp_loc)${NC}"
        has_blocked=true
    elif [[ -n "$perp_loc" ]]; then
        perp_status="${GREEN}✓ Доступ открыт ($perp_loc)${NC}"
    else
        perp_status="${YELLOW}? Не удалось определить${NC}"
    fi
    printf "%-22s %b\n" "Perplexity & Cursor:" "$perp_status"
    echo -e "${CYAN}====================================================================${NC}\n"

    if [ "$has_blocked" = true ]; then
        echo -e "${RED}ВНИМАНИЕ: Одна или несколько нейросетей видят заблокированный регион (RU/BY)!${NC}"
        return 2
    fi
    return 0
}

# Ввод данных прокси
prompt_proxy_credentials() {
    echo ""
    echo -e "${CYAN}Введи данные SOCKS5 прокси.${NC}"
    echo "Можно вставить одной строкой в формате IP:PORT:USER:PASS"
    echo "или просто ввести IP, и скрипт спросит остальное по шагам:"
    read -p "Ввод (IP или IP:PORT:USER:PASS): " RAW_PROXY

    if [[ "$RAW_PROXY" == *:*:*:* ]]; then
        IFS=':' read -r PROXY_IP PROXY_PORT PROXY_USER PROXY_PASS <<< "$RAW_PROXY"
    else
        PROXY_IP="$RAW_PROXY"
        read -p "Порт прокси (например 1080): " PROXY_PORT
        read -p "Логин прокси (оставь пустым, если без пароля): " PROXY_USER
        if [[ -n "$PROXY_USER" ]]; then
            read -p "Пароль прокси: " PROXY_PASS
        else
            PROXY_PASS=""
        fi
    fi

    if [[ -n "$PROXY_USER" ]]; then
        CURL_PROXY="socks5h://${PROXY_USER}:${PROXY_PASS}@${PROXY_IP}:${PROXY_PORT}"
    else
        CURL_PROXY="socks5h://${PROXY_IP}:${PROXY_PORT}"
    fi
}

echo -e "${CYAN}====================================================================${NC}"
echo -e "${CYAN}   ALL-IN-ONE AI Proxy Master (Gemini, ChatGPT, Claude, OpenCode)${NC}"
echo -e "${CYAN}====================================================================${NC}"
echo ""
echo "Куда нужно установить и настроить AI-прокси?"
echo -e "  ${GREEN}1)${NC} Только для ${YELLOW}3x-ui (VLESS / Xray)${NC} — авто-добавление в Исходящие и Маршрутизацию"
echo -e "  ${GREEN}2)${NC} Только для ${YELLOW}Amnezia VPN${NC} (все контейнеры 1.0 / 2.0 / 3.0)"
echo -e "  ${GREEN}3)${NC} Только для консольных CLI на сервере: ${YELLOW}OpenCode, Aider, Claude, agy, codex, cursor${NC}"
echo -e "  ${GREEN}4)${NC} Установить ${YELLOW}ВСЁ СРАЗУ${NC} (3x-ui + Amnezia + CLI утилиты на сервере)"
echo -e "  ${CYAN}5)${NC} ${YELLOW}Тест нейросетей${NC} — проверить, какую страну видит Gemini, ChatGPT, Claude"
echo -e "  ${RED}6)${NC} Удалить прокси и вернуть всё в исходное состояние"
echo ""
read -p "Выбери вариант [1-6]: " MODE_CHOICE

# Режим 5: Только тест
if [[ "$MODE_CHOICE" == "5" ]]; then
    prompt_proxy_credentials
    test_ai_services "$CURL_PROXY" || true
    exit 0
fi

# Режим 6: Удаление и откат
if [[ "$MODE_CHOICE" == "6" ]]; then
    echo -e "\n${YELLOW}Откатываем настройки AI-прокси в исходное состояние...${NC}"
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -t mangle -F PREROUTING 2>/dev/null || true
    systemctl disable --now amnezia-ai-proxy.service 2>/dev/null || true
    systemctl disable --now amnezia-google-proxy.service 2>/dev/null || true
    systemctl disable --now amnezia-google-warp.service 2>/dev/null || true
    systemctl disable --now sing-box.service 2>/dev/null || true
    systemctl disable --now redsocks 2>/dev/null || true
    rm -f /etc/systemd/system/amnezia-ai-proxy.service /usr/local/bin/amnezia-ai-proxy.sh
    rm -f /etc/systemd/system/amnezia-google-proxy.service /usr/local/bin/amnezia-google-proxy.sh
    rm -f /etc/systemd/system/amnezia-google-warp.service /usr/local/bin/amnezia-google-warp.sh
    rm -f /etc/systemd/system/sing-box.service /usr/local/bin/sing-box /usr/bin/sing-box
    rm -rf /etc/sing-box /etc/redsocks.conf
    ipset destroy google_ips_new 2>/dev/null || true
    ipset destroy google_ips 2>/dev/null || true
    systemctl daemon-reload
    if systemctl is-active --quiet docker; then
        systemctl restart docker
    fi
    if [[ -f /etc/x-ui/x-ui.db ]]; then
        python3 - << 'EOF'
import sqlite3, json
conn = sqlite3.connect('/etc/x-ui/x-ui.db')
cur = conn.cursor()
cur.execute("SELECT value FROM settings WHERE key='xrayTemplateConfig'")
row = cur.fetchone()
if row:
    cfg = json.loads(row[0])
    cfg["outbounds"] = [o for o in cfg.get("outbounds", []) if o.get("tag") not in ("ai-proxy", "gemini-proxy", "warp-proxy")]
    if "routing" in cfg and "rules" in cfg["routing"]:
        cfg["routing"]["rules"] = [
            r for r in cfg["routing"]["rules"]
            if r.get("outboundTag") not in ("ai-proxy", "gemini-proxy", "warp-proxy")
            and not (r.get("network") == "udp" and r.get("port") == "443" and ("geoip:google" in r.get("ip", []) or "geosite:openai" in r.get("domain", []) or "geosite:google-gemini" in r.get("domain", [])))
            and not (r.get("outboundTag") in ("direct", "freedom") and "geosite:youtube" in r.get("domain", []))
        ]
    cur.execute("UPDATE settings SET value=? WHERE key='xrayTemplateConfig'", (json.dumps(cfg, indent=2),))
    conn.commit()
conn.close()
EOF
        systemctl restart x-ui 2>/dev/null || true
    fi
    sed -i '/# AI-PROXY-ALIASES-START/,/# AI-PROXY-ALIASES-END/d' ~/.bashrc 2>/dev/null || true
    sed -i '/alias agy=/d' ~/.bashrc 2>/dev/null || true
    echo -e "${GREEN}Готово! Все настройки AI-прокси удалены.${NC}"
    exit 0
fi

# ==============================================================================
# ВЫБОР AI-СЕРВИСОВ ДЛЯ МАРШРУТИЗАЦИИ
# ==============================================================================
echo ""
echo -e "${CYAN}Какие сервисы направлять через прокси?${NC}"
echo -e "  ${GREEN}1)${NC} ${YELLOW}ВСЕ сервисы сразу${NC} (Google/Gemini + OpenAI/ChatGPT + Claude + OpenRouter/Cursor/Aider)"
echo -e "  ${GREEN}2)${NC} Только ${YELLOW}Google & Gemini${NC} (Gemini App, AI Studio, Antigravity agy)"
echo -e "  ${GREEN}3)${NC} Только ${YELLOW}OpenAI & ChatGPT${NC} (ChatGPT App/Web, Codex, Sora, API)"
echo -e "  ${GREEN}4)${NC} Только ${YELLOW}Anthropic Claude${NC} (Claude.ai, Claude Code CLI, API)"
echo -e "  ${GREEN}5)${NC} ${YELLOW}Выбрать вручную через запятую${NC} (например: 2,3)"
echo ""
read -p "Выбери сервисы [1-5]: " SERVICE_CHOICE

ENABLE_GOOGLE=false
ENABLE_OPENAI=false
ENABLE_CLAUDE=false
ENABLE_DEV_TOOLS=false

case "$SERVICE_CHOICE" in
    1)
        ENABLE_GOOGLE=true
        ENABLE_OPENAI=true
        ENABLE_CLAUDE=true
        ENABLE_DEV_TOOLS=true
        ;;
    2)
        ENABLE_GOOGLE=true
        ;;
    3)
        ENABLE_OPENAI=true
        ;;
    4)
        ENABLE_CLAUDE=true
        ;;
    5)
        read -p "Введи номера через запятую (2=Google, 3=OpenAI, 4=Claude, 5=DevTools/OpenRouter): " CUSTOM_CHOICES
        [[ "$CUSTOM_CHOICES" =~ 2 ]] && ENABLE_GOOGLE=true
        [[ "$CUSTOM_CHOICES" =~ 3 ]] && ENABLE_OPENAI=true
        [[ "$CUSTOM_CHOICES" =~ 4 ]] && ENABLE_CLAUDE=true
        [[ "$CUSTOM_CHOICES" =~ 5 ]] && ENABLE_DEV_TOOLS=true
        ;;
    *)
        echo -e "${YELLOW}Выбран вариант по умолчанию: ВСЕ сервисы.${NC}"
        ENABLE_GOOGLE=true
        ENABLE_OPENAI=true
        ENABLE_CLAUDE=true
        ENABLE_DEV_TOOLS=true
        ;;
esac

# Запрос данных прокси
prompt_proxy_credentials

# Автоматический тест нейросетей перед установкой
test_status=0
test_ai_services "$CURL_PROXY" || test_status=$?

if [ $test_status -eq 1 ]; then
    echo -e "${RED}Прерываем установку, так как прокси недоступен.${NC}"
    exit 1
elif [ $test_status -eq 2 ]; then
    read -p "Всё равно продолжить установку с этим прокси? [y/N]: " CONT
    [[ "$CONT" =~ ^[Yy]$ ]] || exit 1
fi

# ==============================================================================
# ФУНКЦИЯ 1: Настройка 3x-ui (с учетом выбранных сервисов + умный обход YouTube)
# ==============================================================================
setup_3x_ui() {
    echo -e "\n${CYAN}---> Настраиваем 3x-ui (VLESS / Xray)...${NC}"
    DB_PATH="/etc/x-ui/x-ui.db"
    if [[ ! -f "$DB_PATH" ]]; then
        echo -e "${RED}База $DB_PATH не найдена! Пропускаем настройку 3x-ui.${NC}"
        return
    fi

    cp "$DB_PATH" "${DB_PATH}.bak"
    echo "Бэкап базы сохранен в ${DB_PATH}.bak"

    ENABLE_GOOGLE="$ENABLE_GOOGLE" ENABLE_OPENAI="$ENABLE_OPENAI" ENABLE_CLAUDE="$ENABLE_CLAUDE" ENABLE_DEV_TOOLS="$ENABLE_DEV_TOOLS" \
    PROXY_IP="$PROXY_IP" PROXY_PORT="$PROXY_PORT" PROXY_USER="$PROXY_USER" PROXY_PASS="$PROXY_PASS" python3 - << 'EOF'
import os, sqlite3, json

db_path = "/etc/x-ui/x-ui.db"
proxy_ip = os.environ["PROXY_IP"]
proxy_port = int(os.environ["PROXY_PORT"])
proxy_user = os.environ.get("PROXY_USER", "")
proxy_pass = os.environ.get("PROXY_PASS", "")

enable_google = os.environ.get("ENABLE_GOOGLE") == "true"
enable_openai = os.environ.get("ENABLE_OPENAI") == "true"
enable_claude = os.environ.get("ENABLE_CLAUDE") == "true"
enable_dev = os.environ.get("ENABLE_DEV_TOOLS") == "true"

conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("SELECT value FROM settings WHERE key='xrayTemplateConfig'")
row = cur.fetchone()
if not row:
    raise SystemExit("Не найден xrayTemplateConfig в базе 3x-ui!")

cfg = json.loads(row[0])
outbounds = cfg.setdefault("outbounds", [])

outbounds = [o for o in outbounds if o.get("tag") not in ("ai-proxy", "gemini-proxy", "warp-proxy")]

direct_idx = next((i for i, o in enumerate(outbounds) if o.get("protocol") == "freedom"), None)
if direct_idx is not None and direct_idx > 0:
    direct_ob = outbounds.pop(direct_idx)
    outbounds.insert(0, direct_ob)

direct_tag = next((o.get("tag") for o in outbounds if o.get("protocol") == "freedom"), "direct")

server_obj = {
    "address": proxy_ip,
    "port": proxy_port
}
if proxy_user:
    server_obj["users"] = [{"user": proxy_user, "pass": proxy_pass}]

outbounds.append({
    "tag": "ai-proxy",
    "protocol": "socks",
    "settings": {
        "servers": [server_obj]
    },
    "streamSettings": {
        "sockopt": {
            "domainStrategy": "UseIPv4"
        }
    }
})
cfg["outbounds"] = outbounds

block_tag = next((o.get("tag") for o in outbounds if o.get("protocol") == "blackhole"), "blocked")

routing = cfg.setdefault("routing", {})
rules = routing.setdefault("rules", [])

rules = [
    r for r in rules
    if r.get("outboundTag") not in ("ai-proxy", "gemini-proxy", "warp-proxy")
    and not (r.get("network") == "udp" and r.get("port") == "443" and ("geoip:google" in r.get("ip", []) or "geosite:openai" in r.get("domain", []) or "geosite:google-gemini" in r.get("domain", [])))
    and not (r.get("outboundTag") in ("direct", direct_tag) and "geosite:youtube" in r.get("domain", []))
]

ai_domains = []
ai_ips = []

# Если включен Google: YouTube направляем напрямую без рекламы (RU-регион сервера)
new_rules = []
if enable_google:
    new_rules.append({
        "type": "field",
        "outboundTag": direct_tag,
        "domain": [
            "geosite:youtube",
            "domain:youtube.com",
            "domain:googlevideo.com",
            "domain:youtu.be",
            "domain:ytimg.com",
            "domain:youtubei.googleapis.com",
            "domain:youtubekids.com",
            "domain:youtube-nocookie.com",
            "domain:wide-youtube.l.google.com",
            "domain:yt.be",
            "domain:gvt1.com",
            "domain:gvt2.com",
            "domain:gvt3.com"
        ]
    })
    ai_domains.extend([
        "geosite:google-gemini",
        "geosite:google",
        "domain:gemini.google.com",
        "domain:bard.google.com",
        "domain:aistudio.google.com",
        "domain:generativelanguage.googleapis.com",
        "domain:proactivebackend-pa.googleapis.com",
        "domain:alkalimakersuite-pa.clients6.google.com",
        "domain:antigravity.google",
        "domain:cloudcode-pa.googleapis.com",
        "domain:cloudaicompanion.googleapis.com"
    ])
    ai_ips.append("geoip:google")

if enable_openai:
    ai_domains.extend([
        "geosite:openai",
        "domain:openai.com",
        "domain:chatgpt.com",
        "domain:oaistatic.com",
        "domain:oaiusercontent.com",
        "domain:sora.com",
        "domain:openai.org"
    ])

if enable_claude:
    ai_domains.extend([
        "geosite:anthropic",
        "domain:anthropic.com",
        "domain:claude.ai",
        "domain:claude.com",
        "domain:claudeusercontent.com",
        "domain:statsig.anthropic.com"
    ])
    ai_ips.append("160.79.104.0/23")

if enable_dev:
    ai_domains.extend([
        "domain:openrouter.ai",
        "domain:groq.com",
        "domain:together.xyz",
        "domain:x.ai",
        "domain:grok.com",
        "domain:cursor.sh",
        "domain:cursor.com",
        "domain:perplexity.ai",
        "domain:copilot.microsoft.com"
    ])

if ai_domains:
    new_rules.append({
        "type": "field",
        "outboundTag": block_tag,
        "network": "udp",
        "port": "443",
        "domain": ai_domains
    })
if ai_ips:
    new_rules.append({
        "type": "field",
        "outboundTag": block_tag,
        "network": "udp",
        "port": "443",
        "ip": ai_ips
    })
if ai_domains:
    new_rules.append({
        "type": "field",
        "outboundTag": "ai-proxy",
        "domain": ai_domains
    })
if ai_ips:
    new_rules.append({
        "type": "field",
        "outboundTag": "ai-proxy",
        "ip": ai_ips
    })

insert_pos = 1 if (rules and "geoip:private" in rules[0].get("ip", [])) else 0
for idx, rule in enumerate(new_rules):
    rules.insert(insert_pos + idx, rule)

cfg["routing"]["rules"] = rules

cur.execute("UPDATE settings SET value=? WHERE key='xrayTemplateConfig'", (json.dumps(cfg, indent=2),))
conn.commit()
conn.close()
print("Конфигурация 3x-ui успешно обновлена в БД!")
EOF

    systemctl restart x-ui
    echo -e "${GREEN}✓ 3x-ui перезапущен! YouTube идет напрямую без рекламы, AI-сервисы через прокси.${NC}"
}

# ==============================================================================
# ФУНКЦИЯ 2: Настройка Amnezia VPN (sing-box transparent routing с SNI-сниффингом)
# ==============================================================================
setup_amnezia() {
    echo -e "\n${CYAN}---> Настраиваем Amnezia VPN с умной маршрутизацией через sing-box...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq ipset jq curl dnsutils >/dev/null 2>&1 || true

    # Отключаем старый redsocks при наличии
    systemctl disable --now redsocks 2>/dev/null || true
    systemctl disable --now amnezia-google-proxy.service 2>/dev/null || true
    rm -f /etc/systemd/system/amnezia-google-proxy.service /usr/local/bin/amnezia-google-proxy.sh

    # Установка sing-box, если не установлен
    if ! command -v sing-box >/dev/null 2>&1 || [[ ! -f /usr/local/bin/sing-box ]]; then
        echo -e "${YELLOW}Устанавливаем sing-box...${NC}"
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64|amd64) SB_ARCH="amd64" ;;
            aarch64|arm64) SB_ARCH="arm64" ;;
            *) SB_ARCH="amd64" ;;
        esac
        SB_VER="1.14.4"
        curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/sing-box-${SB_VER}-linux-${SB_ARCH}.tar.gz" | tar -xz -C /tmp/
        mv "/tmp/sing-box-${SB_VER}-linux-${SB_ARCH}/sing-box" /usr/local/bin/sing-box
        chmod +x /usr/local/bin/sing-box
        rm -rf "/tmp/sing-box-${SB_VER}-linux-${SB_ARCH}"
    fi

    # Создаем глобальный симлинк во избежание проблем с PATH в неинтерактивных сессиях
    ln -sf /usr/local/bin/sing-box /usr/bin/sing-box

    # Генерация конфигурации sing-box
    mkdir -p /etc/sing-box
    AUTH_JSON=""
    if [[ -n "$PROXY_USER" ]]; then
        AUTH_JSON=",
      \"username\": \"${PROXY_USER}\",
      \"password\": \"${PROXY_PASS}\""
    fi

    cat << EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "redirect",
      "tag": "redirect-in",
      "listen": "0.0.0.0",
      "listen_port": 12345
    },
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 2080
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "socks",
      "tag": "ai-proxy",
      "server": "${PROXY_IP}",
      "server_port": ${PROXY_PORT}${AUTH_JSON}
    }
  ],
  "route": {
    "rules": [
      {
        "action": "sniff"
      },
      {
        "inbound": "mixed-in",
        "outbound": "ai-proxy"
      },
      {
        "domain_suffix": [
          "youtube.com",
          "googlevideo.com",
          "youtu.be",
          "ytimg.com",
          "yt.be",
          "ggpht.com",
          "youtubei.googleapis.com",
          "youtubekids.com",
          "youtube-nocookie.com",
          "wide-youtube.l.google.com",
          "nhacmp3youtube.com",
          "gvt1.com",
          "gvt2.com",
          "gvt3.com",
          "video.google.com"
        ],
        "outbound": "direct"
      }
    ],
    "final": "ai-proxy"
  }
}
EOF

    # Валидация конфигурации перед созданием службы
    /usr/local/bin/sing-box check -c /etc/sing-box/config.json

    # Создание службы sing-box
    cat << 'EOF' > /etc/systemd/system/sing-box.service
[Unit]
Description=sing-box service for Amnezia AI Smart Routing
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=3s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now sing-box.service

    # Создание скрипта заполнения ipset и правил iptables (с атомарной заменой)
    cat << EOF > /usr/local/bin/amnezia-ai-proxy.sh
#!/bin/bash
set -e

# Атомарное обновление ipset через временный сет (без разрыва существующих соединений)
ipset create google_ips hash:net -exist
ipset create google_ips_new hash:net -exist
ipset flush google_ips_new

ENABLE_GOOGLE=$ENABLE_GOOGLE
ENABLE_OPENAI=$ENABLE_OPENAI
ENABLE_CLAUDE=$ENABLE_CLAUDE
ENABLE_DEV_TOOLS=$ENABLE_DEV_TOOLS

AI_HOSTS=()

if [ "\$ENABLE_GOOGLE" = true ]; then
    # Базовые надежные подсети Google
    for cidr in 142.250.0.0/15 172.217.0.0/16 172.253.0.0/16 216.58.192.0/19 74.125.0.0/16 108.177.0.0/17 64.233.160.0/19 209.85.128.0/17; do
        ipset add google_ips_new "\$cidr" -exist 2>/dev/null || true
    done
    # Динамический пул подсетей Google
    for ip in \$(curl -m 5 -s https://www.gstatic.com/ipranges/goog.json 2>/dev/null | jq -r '.prefixes[].ipv4Prefix | select(. != null)' 2>/dev/null || true); do
        ipset add google_ips_new "\$ip" -exist 2>/dev/null || true
    done
    AI_HOSTS+=("gemini.google.com" "aistudio.google.com" "generativelanguage.googleapis.com" "proactivebackend-pa.googleapis.com" "alkalimakersuite-pa.clients6.google.com" "antigravity.google" "cloudcode-pa.googleapis.com" "cloudaicompanion.googleapis.com")
fi

if [ "\$ENABLE_OPENAI" = true ]; then
    AI_HOSTS+=("chatgpt.com" "api.openai.com" "auth.openai.com" "platform.openai.com" "ios.chat.openai.com" "android.chat.openai.com" "ab.chatgpt.com" "ws.chatgpt.com" "chat.openai.com" "oaistatic.com" "oaiusercontent.com" "sora.com")
fi

if [ "\$ENABLE_CLAUDE" = true ]; then
    ipset add google_ips_new "160.79.104.0/23" -exist 2>/dev/null || true
    AI_HOSTS+=("claude.ai" "api.anthropic.com" "console.anthropic.com" "statsig.anthropic.com")
fi

if [ "\$ENABLE_DEV_TOOLS" = true ]; then
    AI_HOSTS+=("openrouter.ai" "api.groq.com" "api.together.xyz" "grok.com" "api.x.ai" "perplexity.ai" "api2.cursor.sh")
fi

for host in "\${AI_HOSTS[@]}"; do
    for ip in \$(dig +short +time=2 +tries=1 A "\$host" @1.1.1.1 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true); do
        ipset add google_ips_new "\$ip" -exist 2>/dev/null || true
    done
done

# Атомарно переключаем актуальный ipset
ipset swap google_ips_new google_ips
ipset destroy google_ips_new 2>/dev/null || true

for SUBNET in 172.16.0.0/12 10.8.0.0/16 172.29.172.0/24; do
    iptables -C INPUT -s "\$SUBNET" -p tcp --dport 12345 -j ACCEPT 2>/dev/null || \
    iptables -I INPUT -s "\$SUBNET" -p tcp --dport 12345 -j ACCEPT

    iptables -t mangle -C PREROUTING -s "\$SUBNET" -m set --match-set google_ips dst -p udp --dport 443 -j DROP 2>/dev/null || \
    iptables -t mangle -I PREROUTING -s "\$SUBNET" -m set --match-set google_ips dst -p udp --dport 443 -j DROP

    iptables -t nat -C PREROUTING -s "\$SUBNET" -m set --match-set google_ips dst -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345 2>/dev/null || \
    iptables -t nat -I PREROUTING -s "\$SUBNET" -m set --match-set google_ips dst -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345
done
EOF

    chmod +x /usr/local/bin/amnezia-ai-proxy.sh

    cat << 'EOF' > /etc/systemd/system/amnezia-ai-proxy.service
[Unit]
Description=Route Amnezia AI traffic through SOCKS5 Proxy
After=network-online.target docker.service sing-box.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=/usr/local/bin/amnezia-ai-proxy.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now amnezia-ai-proxy.service
    echo -e "${GREEN}✓ Amnezia VPN настроена! YouTube идет напрямую без рекламы, AI-сервисы через прокси.${NC}"
}

# ==============================================================================
# ФУНКЦИЯ 3: Настройка консольных CLI на сервере
# ==============================================================================
setup_cli_tools() {
    echo -e "\n${CYAN}---> Настраиваем консольные CLI и агент-утилиты на сервере...${NC}"
    sed -i '/# AI-PROXY-ALIASES-START/,/# AI-PROXY-ALIASES-END/d' ~/.bashrc 2>/dev/null || true
    sed -i '/alias agy=/d' ~/.bashrc 2>/dev/null || true

    cat << EOF >> ~/.bashrc
# AI-PROXY-ALIASES-START
proxyrun() {
    HTTPS_PROXY="${CURL_PROXY}" HTTP_PROXY="${CURL_PROXY}" ALL_PROXY="${CURL_PROXY}" "\$@"
}
alias agy="HTTPS_PROXY=${CURL_PROXY} HTTP_PROXY=${CURL_PROXY} ALL_PROXY=${CURL_PROXY} agy"
alias claude="HTTPS_PROXY=${CURL_PROXY} HTTP_PROXY=${CURL_PROXY} ALL_PROXY=${CURL_PROXY} claude"
alias codex="HTTPS_PROXY=${CURL_PROXY} HTTP_PROXY=${CURL_PROXY} ALL_PROXY=${CURL_PROXY} codex"
alias gemini="HTTPS_PROXY=${CURL_PROXY} HTTP_PROXY=${CURL_PROXY} ALL_PROXY=${CURL_PROXY} gemini"
alias opencode="HTTPS_PROXY=${CURL_PROXY} HTTP_PROXY=${CURL_PROXY} ALL_PROXY=${CURL_PROXY} opencode"
alias aider="HTTPS_PROXY=${CURL_PROXY} HTTP_PROXY=${CURL_PROXY} ALL_PROXY=${CURL_PROXY} aider"
alias cursor="HTTPS_PROXY=${CURL_PROXY} HTTP_PROXY=${CURL_PROXY} ALL_PROXY=${CURL_PROXY} cursor"
# AI-PROXY-ALIASES-END
EOF
    echo -e "${GREEN}✓ Добавлены алиасы: opencode, aider, claude, codex, agy, gemini, cursor!${NC}"
    echo -e "${CYAN}💡 Функция 'proxyrun': запуск любой команды через прокси (например 'proxyrun opencode').${NC}"
    echo -e "   (Выполни ${YELLOW}source ~/.bashrc${NC}, чтобы обновить текущее окно терминала)."
}

case "$MODE_CHOICE" in
    1) setup_3x_ui ;;
    2) setup_amnezia ;;
    3) setup_cli_tools ;;
    4)
        [[ -f /etc/x-ui/x-ui.db ]] && setup_3x_ui || echo -e "${YELLOW}3x-ui не найден на сервере, пропускаем.${NC}"
        setup_amnezia
        setup_cli_tools
        ;;
    *) echo -e "${RED}Неверный выбор!${NC}"; exit 1 ;;
esac

echo ""
echo -e "${GREEN}====================================================================${NC}"
echo -e "${GREEN}   ВСЁ ГОТОВО! AI-Прокси успешно подключен и настроен!${NC}"
echo -e "${GREEN}====================================================================${NC}"
