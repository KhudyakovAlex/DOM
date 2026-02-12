## Скачивание карты с сервиса

https://download.geofabrik.de/russia.html

### Актуальные данные с OSM

OSM данные обновляются постоянно (каждую минуту добавляются новые правки от контрибьютеров).
На geofabrik.de файлы обновляются:
Ежедневно (страны, большие регионы) ✅ свежие данные
Еженедельно (меньшие регионы)
Ежемесячно (архив)

### Обработка

конвертим .osm.pbf в .pmtiles
между при необходмости отфильтровываем лишнее
просмотр .pmtiles - pmtiles.io

1) Вырезка из большого .osm.pbf: делали osmium extract в Docker на Windows, образ stefda/osmium-tool, по bbox Ярославля.
2) Фильтрация данных: osmium tags-filter → получили отдельный yaroslavl_filt.osm.pbf, оставили здания (building), дороги (highway), воду (waterway, natural=water, water, waterway=riverbank).
3) Конвертация в .pmtiles: Planetiler в Docker, образ ghcr.io/onthegomap/planetiler:latest, запускали с --osm-path=/data/yaroslavl_filt.osm.pbf --output=/data/yaroslavl.pmtiles. Первый раз добавили --download, чтобы скачать доп. источники профиля (water polygons, lake centerlines, Natural Earth).

## Открытие карты у нас

## Переключение режимов отображения

## Вывод окон поверх карты

## Получение координат кликов

## Добавление 2D-фигуры

## Добавление 2D-линии

## Обработка нажатий на 2D-объекты

## Добавление именованных и струтурированных 3D-моделей через .glb

## Обработка нажатий на 3D-модель и ее элементы

## Задание таректории в 3D

## Рисование по 3D-траектории

## Проход нажатий через дома