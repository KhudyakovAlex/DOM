# 🚀 Быстрый старт АСУНО E-commerce

## Установка и запуск

### Вариант 1: Docker Compose (рекомендуется)

```bash
# В корне проекта
docker-compose up -d

# Проверка
curl http://localhost:8000/health
# Ответ: {"status":"ok"}
```

**Приложение готово:**
- Backend API: http://localhost:8000
- API документация: http://localhost:8000/docs
- PostgreSQL: localhost:5432 (логин: postgres, пароль: postgres)

### Вариант 2: Локальная разработка

#### Backend

```bash
cd backend

# Установка зависимостей Python
pip install -r requirements.txt

# Запуск PostgreSQL (отдельное окно/терминал)
docker run --name asuno_postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=asuno_db \
  -p 5432:5432 \
  -d postgres:15-alpine

# Запуск сервера
uvicorn main:app --reload
```

#### Frontend

```bash
cd frontend

npm install
npm run dev
```

Откройте http://localhost:5173

## 🧪 Тестирование

### Регистрация и вход

1. Откройте http://localhost:5173
2. Нажмите "Регистрация"
3. Введите:
   - Email: `test@example.com`
   - Пароль: `password123`
4. Зарегистрируйтесь
5. Вы автоматически войдёте
6. Нажмите "Перейти в панель" → попадёте на Dashboard

### API тестирование через curl

```bash
# Регистрация
curl -X POST http://localhost:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"pass123"}'

# Вход
curl -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"pass123"}'

# Ответ:
# {
#   "access_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
#   "refresh_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
#   "token_type": "bearer"
# }

# Получить профиль (замени TOKEN на access_token)
curl -X GET "http://localhost:8000/api/auth/me?token=TOKEN" \
  -H "Authorization: Bearer TOKEN"
```

## 📊 БД схема

```
dom_auth схема:
├── roles (id, name, created_at)
├── users (id, email, password_hash, is_active, role_id, created_at, updated_at)
└── refresh_tokens (id, user_id, token, expires_at, created_at)

dom_domain схема:
└── (пока пуста - добавляй таблицы для товаров, заказов и т.д.)
```

## ❌ Остановка приложения

```bash
# Docker Compose
docker-compose down

# Если нужно удалить данные БД
docker-compose down -v
```

## 🔧 Что дальше?

1. **Добавить таблицы в dom_domain:**
   - products, categories, orders, cart и т.д.

2. **Реализовать RLS политики** для безопасности

3. **Создать эндпойнты для товаров и заказов**

4. **Добавить админ панель**

5. **Подключить платёжную систему**

Готово? Дай знать, что дальше создавать! 🚀
