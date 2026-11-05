# 🚀 AI Proxy Router

> **Интеллектуальная выборочная маршрутизация трафика популярных нейросетей через SOCKS5-прокси на серверах с 3x-ui (VLESS / Xray) и Amnezia VPN (AmneziaWG / WireGuard).**  
> Решает проблему региональных ограничений (*«Страна не поддерживается»*, блокировки Google AI Studio, Gemini `"GL":"RU"`, Claude, ChatGPT) на VPS любых хостеров. Через прокси направляется **только трафик AI-сервисов**, а весь остальной интернет и YouTube работают напрямую на полной скорости сервера без буферизации.

[![Bash](https://img.shields.io/badge/Language-Bash%20Script-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![3x-ui](https://img.shields.io/badge/VPN%20Core-3x--ui%20(Xray)-0088CC)](https://github.com/MHSanaei/3x-ui)
[![Amnezia](https://img.shields.io/badge/VPN%20Core-AmneziaWG-FF5722)](https://amnezia.org/)
[![sing-box](https://img.shields.io/badge/Router-sing--box-F58220)](https://sing-box.sagernet.org/)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## ⚡ Быстрый старт (Установка в 1 строку)

Запустите скрипт на вашем сервере под пользователем `root`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/pylcov/ai-proxy-router/main/setup-ai-proxy.sh)
```

> [!TIP]
> **Автономность**: скрипт автоматически определит тип установленного VPN (3x-ui или Amnezia), проверит наличие необходимых утилит (`sing-box`, `ipset`, `iptables`, `jq`) и сам установит недостающие.  
> Данные вашего SOCKS5-прокси можно вставить **одной строкой** в формате `IP:PORT:USER:PASS` либо ввести интерактивно по шагам.

---

## 📌 Содержание

- [Зачем нужен AI Proxy Router (Сравнение)](#-зачем-нужен-ai-proxy-router)
- [Поддерживаемые сервисы](#-поддерживаемые-сервисы)
- [Ключевые технические возможности](#-ключевые-технические-возможности)
- [Работа с консольными утилитами (proxyrun)](#-работа-с-консольными-утилитами-на-сервере)
- [Встроенная диагностика доступности](#-встроенная-диагностика-нейросетей)
- [Удаление и чистый откат](#-удаление-и-откат)

---

## 💡 Зачем нужен AI Proxy Router?

При аренде VPS в Европе (Нидерланды, Германия, Финляндия и др.) IP-адреса хостинг-провайдеров часто имеют региональную метку РФ в базах GeoIP Google/OpenAI либо заблокированы ИИ-платформами. 

Стандартная попытка «завернуть весь трафик сервера в сторонний прокси» приводит к резкому падению скорости, потере доступа к локальным ресурсам и иностранной рекламе на YouTube.

### Сравнение подходов:

| Параметр | Обычные скрипты «Весь трафик в прокси» | AI Proxy Router |
|---|---|---|
| **Трафик нейросетей** | ✅ Идёт в прокси | ✅ **Идёт в прокси (Gemini, Claude, ChatGPT, Cursor)** |
| **YouTube (4K/8K)** | ❌ Тормозит через узкий канал, иностранная реклама | ⚡ **Напрямую на скорости порта (Zero Ads, No Buffering)** |
| **Скорость обычных сайтов** | ❌ Ограничена каналом прокси | ⚡ **Максимальная скорость канала вашего VPS** |
| **CLI-утилиты на сервере** | ❌ Требуют ручной настройки переменных окружения | 🛠 **Готовые алиасы (`agy`, `claude`) и утилита `proxyrun`** |
| **Автозапуск после ребута** | ⚠️ Ручные скрипты часто сбиваются | 🔒 **Надёжные systemd-службы и атомарный `ipset swap`** |

---

## 🎯 Поддерживаемые сервисы

* **Google AI**: Gemini (Web и Mobile App), Google AI Studio, Antigravity CLI (`agy`), Google Cloud Code, бэкенды Cloud AI.
* **OpenAI**: ChatGPT (Web, iOS, Android), OpenAI API, Codex CLI, Sora.
* **Anthropic**: Claude.ai, Claude API, консольный агент Claude Code (`claude`).
* **Инструменты разработки**: Cursor IDE, OpenCode, Aider, OpenRouter, Groq, Together AI, Perplexity, GitHub Copilot.
* **YouTube**: Умный обход — видеопотоки Google Video и CDN всегда идут напрямую в обход прокси.

---

## ⚙️ Ключевые технические возможности

```
[ Клиент: ПК / Смартфон ]
           │
           ▼
┌── Ваш VPS-сервер (3x-ui / Amnezia) ──────────────────────────────────┐
│                                                                      │
│   DNS / SNI Анализатор трафика (sing-box / Xray routing)             │
│   ├── Домены AI (gemini, claude, openai, cursor) ──► [ SOCKS5 Прокси ]
│   └── YouTube и обычные сайты (direct) ───────────► [ Прямой интернет ]
└──────────────────────────────────────────────────────────────────────┘
```

### 1. Интеграция с 3x-ui (Xray / VLESS)
* Напрямую модифицирует базу `/etc/x-ui/x-ui.db` без необходимости ручной настройки правил в браузере.
* Создаёт отдельное исходящее подключение `ai-proxy` со стратегией `UseIPv4`.
* Блокирует QUIC (UDP 443) для нейросетей, заставляя клиентские приложения работать через надёжный TCP без утечки реального IP.

### 2. Интеграция с Amnezia VPN (AmneziaWG / WireGuard)
* Поддерживает любые контейнеры AmneziaWG (версий 1.0, 2.0 и 3.0).
* Маршрутизирует трафик через связку **`sing-box` + `ipset` + `iptables`**.
* Использует **атомарное переключение ipset (`swap`)**, исключая обрывы соединений при обновлениях списков.
* Регистрирует службы `sing-box.service` и `amnezia-ai-proxy.service` в `systemd` для стабильного автозапуска.

---

## 💻 Работа с консольными утилитами на сервере

Скрипт поднимает локальный интерфейс **`127.0.0.1:2080`** (SOCKS5/HTTP) и автоматически прописывает алиасы в `~/.bashrc`:

```bash
# Быстрый запуск консольных агентов через прокси:
agy              # Antigravity CLI
claude           # Claude Code
cursor           # Cursor IDE
gemini           # Gemini CLI
opencode         # OpenCode
aider            # Aider
```

### Универсальная утилита `proxyrun`
Позволяет выполнить **любую произвольную команду или скрипт** через AI-прокси:
```bash
proxyrun curl https://chatgpt.com/cdn-cgi/trace
proxyrun python my_ai_script.py
proxyrun npm run dev
```

---

## 🔍 Встроенная диагностика нейросетей

Перед установкой (а также в любое время через пункт меню **`5) Тест нейросетей`**) скрипт выполняет глубокую диагностику вашего прокси:

* **Google / Gemini**: проверяет региональный тег `GL` и отправляет тестовый запрос в Gemini API (`generativelanguage.googleapis.com`).
* **OpenAI / ChatGPT**: проверяет Cloudflare Trace (`chatgpt.com/cdn-cgi/trace`), определяя точную страну (`loc`) и дата-центр (`colo`).
* **Anthropic Claude**: тестирует шлюз `claude.ai`.
* **Perplexity**: тестирует маршрутизацию запросов.
* **IP Info**: отображает реальный внешний IP, хостинг-провайдера и город выхода.

---

## 🔄 Удаление и откат

В главном меню скрипта предусмотрен пункт **`6) Удалить прокси`**. Он в 1 клик:
1. Удаляет созданные исходящие подключения и правила маршрутизации из `3x-ui`.
2. Очищает таблицы `iptables` и наборы `ipset`.
3. Корректно останавливает и удаляет службы `sing-box` и `amnezia-ai-proxy`.
4. Удаляет добавленные алиасы и `proxyrun` из `~/.bashrc`.
5. Возвращает сервер в чистое исходное состояние.

---

## 📄 Лицензия

Распространяется под свободной лицензией **MIT**. См. файл [LICENSE](LICENSE).
