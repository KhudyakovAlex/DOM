# DOM

Учебный fullstack-проект (Vue 3 + FastAPI + Postgres) с первой задачей: **показать карту (MapLibre + PMTiles) на единственной странице**.

## Запуск

- Запуск всего: `START.bat`
- Frontend: `http://localhost:5173`
- Backend: `http://localhost:8000` (docs: `http://localhost:8000/docs`)

## Карта (PMTiles)

Большие файлы в git **не кладём**.

1) Положи файл карты сюда:
- `backend/app/static/pmtiles/yaroslavl.pmtiles`

2) Backend раздаёт его так:
- `GET /api/tiles/yaroslavl.pmtiles` (поддерживает Range/206)

## Стек
- Frontend: Vue 3, Vite, MapLibre GL, pmtiles
- Backend: FastAPI (Docker Compose + Postgres)
