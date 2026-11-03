# 🚀 AI Proxy Router (3x-ui / Xray & Amnezia VPN)

Автоматический скрипт маршрутизации трафика AI-сервисов (**Google Gemini**, **OpenAI ChatGPT/Codex**, **Anthropic Claude & Claude Code**, **OpenCode**, **Aider**, **Cursor**, **OpenRouter**) через чистый SOCKS5-прокси на серверах с **3x-ui (VLESS/Xray)** и **Amnezia VPN (AmneziaWG/WireGuard)**.

Позволяет решить проблему *"Страна не поддерживается"* (GeoIP `"GL":"RU"`) на VPS в Нидерландах, Германии и у популярных хостеров без потери скорости на основном трафике.

---

## ⚡ Быстрый запуск (в 1 команду)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/pylcov/ai-proxy-router/main/setup-ai-proxy.sh)
```

> **Примечание:** `git` на сервере не требуется! Скрипт сам автоматически проверит и установит все недостающие пакеты (`python3`, `jq`, `dnsutils`, `ipset`, `iptables`, `redsocks`).

---

## 🛠 Возможности

1. **Автоматизация 3x-ui (Xray/VLESS)**:
   - Без входа в веб-панель сам вносит изменения в SQLite базу `/etc/x-ui/x-ui.db`.
   - Добавляет `ai-proxy` в Outbounds с принудительной стратегией `UseIPv4`.
   - Автоматически создает правила маршрутизации (Routing Rules) для всех AI-доменов, шлюзов и IP.
   - Блокирует QUIC (UDP 443) для AI, заставляя мобильные приложения ходить строго по TCP через прокси.

2. **Поддержка Amnezia VPN**:
   - Работает со всеми контейнерами (AmneziaWG 1.0, 2.0, 3.0).
   - Связывает контейнеры с прокси через связку `redsocks` + `ipset` + `iptables`.
   - Создает `systemd`-сервис для автозапуска после перезагрузки сервера.

3. **CLI-агенты на самом сервере**:
   - Автоматически настраивает алиасы в `~/.bashrc` для:
     - `opencode` (OpenCode CLI)
     - `aider` (Aider AI pair programmer)
     - `claude` (Anthropic Claude Code)
     - `codex` (OpenAI Codex CLI)
     - `agy` (Google Antigravity CLI)
     - `gemini` (Gemini CLI)
     - `cursor` (Cursor CLI)
   - **Универсальная обертка `proxyrun`**: позволяет запустить **любую** команду, скрипт или приложение через прокси:
     ```bash
     proxyrun opencode
     proxyrun python train.py
     proxyrun npm start
     ```

4. **Интерактивное меню**:
   - Выбор: 3x-ui, Amnezia, CLI или ВСЁ СРАЗУ.
   - Проверка статуса прокси и страны в базе Google (`"GL"`) перед установкой.
   - Возможность полного отката (удаления) всех правил в 1 клик.

---

## 📋 Поддерживаемые сервисы

- **Google**: Gemini (веб и мобильное приложение), AI Studio, Antigravity (`agy`), Google Cloud Code.
- **OpenAI**: ChatGPT (веб, iOS, Android), OpenAI API, Codex CLI, Sora.
- **Anthropic**: Claude.ai, Claude API, Claude Code (`claude`).
- **Разработка & CLI**: OpenCode, Aider, Cursor, OpenRouter, Groq, Together AI, Perplexity, Microsoft Copilot.
