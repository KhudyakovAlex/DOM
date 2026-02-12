# Запуск АСУНО на Ubuntu (Production)

## Требования
- Ubuntu 20.04+ 
- Docker & Docker Compose установлены
- Node.js 18+ (для Frontend)
- SSH/PuTTY доступ

## Установка окружения

### 1. Установка Docker & Docker Compose (если нет)

```bash
sudo apt update
sudo apt install -y docker.io docker-compose

# Дать права текущему юзеру
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Копирование файлов на сервер

**Используй WinSCP:**
- Подключись SSH (IP, user, password)
- Скопируй папки: `backend/`, `frontend/`, `docker-compose.yml`
- На сервере: `~/DOM/`

### 3. Запуск Backend + PostgreSQL (Docker)

```bash
cd ~/DOM

# Проверить структуру
ls -la

# Запустить контейнеры
docker-compose up -d

# Проверить статус
docker-compose ps
# Оба контейнера должны быть в статусе "Up"
```

**Порты:**
- Backend API: `http://server-ip:8000`
- API Docs: `http://server-ip:8000/docs`
- PostgreSQL: `server-ip:5433`

### 4. Запуск Frontend (Node.js)

```bash
cd ~/DOM/frontend

# Установка зависимостей (если первый раз)
npm install

# Запуск в фоне (работает даже если закрыть PuTTY)
nohup npm run dev -- --host > ~/DOM/frontend/frontend.log 2>&1 &

# Проверить логи
tail -f ~/DOM/frontend/frontend.log
# Должно быть: "VITE v5.x.x ready"
```

**Порты:**
- Frontend: `http://server-ip:5174` (или 5173, если свободно)

### 5. Проверка

В браузере на Windows:

```
http://10.10.7.188:5174     # Frontend (замени IP)
http://10.10.7.188:8000     # Backend API
http://10.10.7.188:8000/docs # API документация
```

## Контроль (через PuTTY)

```bash
# Статус контейнеров
docker-compose ps

# Статус Frontend
ps aux | grep "npm run dev"

# Логи Backend
docker-compose logs backend --tail 20

# Логи Frontend
tail ~/DOM/frontend/frontend.log

# Остановить всё
docker-compose down

# Убить Frontend процесс
pkill -f "npm run dev"
```

## Важные файлы для правки (если нужно)

- `docker-compose.yml` — порты, образы
- `backend/.env` — DATABASE_URL, SECRET_KEY
- `backend/config.py` — database_url
- `frontend/vite.config.js` — proxy к API

## Быстрый перезапуск

```bash
# Backend (Docker)
cd ~/DOM
docker-compose restart

# Frontend (Node)
cd ~/DOM/frontend
pkill -f "npm run dev"
nohup npm run dev -- --host > ~/DOM/frontend/frontend.log 2>&1 &
```

## Автостарт при перезагрузке сервера

### Backend (Docker) — запустится автоматически

Docker контейнеры имеют флаг `restart: unless-stopped` в `docker-compose.yml`, поэтому после перезагрузки они запустятся автоматически.

### Frontend (systemd сервис)

**Создай systemd сервис для Frontend:**

```bash
sudo cat > /etc/systemd/system/asuno-frontend.service << 'EOF'
[Unit]
Description=АСУНО Frontend Vite
After=network.target docker.service

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/DOM/frontend
ExecStart=/usr/bin/npm run dev -- --host
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable asuno-frontend
sudo systemctl start asuno-frontend

# Проверить статус
sudo systemctl status asuno-frontend
```

**После перезагрузки сервера всё запустится автоматически:**

```bash
# Проверить статусы
docker-compose ps
sudo systemctl status asuno-frontend
```

**Управление сервисом:**

```bash
# Остановить
sudo systemctl stop asuno-frontend

# Запустить
sudo systemctl start asuno-frontend

# Перезагрузить
sudo systemctl restart asuno-frontend

# Посмотреть логи
sudo journalctl -u asuno-frontend -n 50
sudo journalctl -u asuno-frontend -f  # live логи
```

## Порты по умолчанию

| Сервис | Порт | URL |
|--------|------|-----|
| Backend API | 8000 | http://server-ip:8000 |
| Frontend Vite | 5173 | http://server-ip:5173 |
| PostgreSQL | 5433 | server-ip:5433 |
| API Docs | 8000 | http://server-ip:8000/docs |

## Тестирование

1. Откройи http://10.10.7.188:5173 в браузере
2. Нажми "Регистрация"
3. Введи email и пароль
4. Зарегистрируйся → автоматический вход
5. Перейди в панель управления

**Готово! 🚀**
