# Обводка 3D-модели через Silhouette Edges (2D-слой)

## Идея

Обводка рисуется **на 2D-слое поверх 3D-сцены** (Canvas 2D), а не в 3D. Для этого:
1. Находим **silhouette edges** — рёбра на границе лицевых и тыловых граней.
2. Проецируем их в экранные координаты.
3. Рисуем 2D-линии на прозрачном canvas-оверлее.

## Контекст проекта

- **Карта:** MapLibre GL с custom 3D layer
- **3D:** Three.js, камера без `position` (только `projectionMatrix` от MapLibre)
- **Модели:** GLTF, добавляются как `THREE.Group` в сцену
- **Hover:** Raycaster определяет, какая модель под курсором (`hoveredTankAnchor`)

## Алгоритм

### 1. Поиск silhouette edges

**Silhouette edge** — ребро между двумя треугольниками, у которых один лицевой (смотрит на камеру), другой тыловой (смотрит от камеры).

Для каждого меша:
1. Строим карту `edgeFaces`: ключ `"i,j"` (индексы вершин ребра, i < j), значение — массив нормалей прилегающих граней (обычно 2).
2. Для каждого треугольника: считаем нормаль, добавляем её в `addEdge` для трёх рёбер.
3. Для каждого ребра с двумя нормалями: проверяем `dot(normal1, viewDir) * dot(normal2, viewDir) < 0` — тогда ребро silhouette.
4. Позицию камеры для `viewDir` можно взять так:
   ```js
   const camPos = new THREE.Vector3(0, 0, 0.5).unproject(camera)
   viewDir = camPos - midEdge
   ```

### 2. Проекция в экран

```js
const toScreen = (v) => {
  const p = v.clone().project(camera)  // NDC [-1,1]
  return [
    (p.x + 1) * 0.5 * width,   // пиксели X
    (1 - p.y) * 0.5 * height,  // пиксели Y (flip)
    p.z                         // для проверки видимости
  ]
}
```

Фильтруем сегменты: `p.z` в [-1, 1], хотя бы одна вершина в видимой области экрана.

### 3. 2D canvas-оверлей

- Создаём `<canvas>`, добавляем в контейнер карты как дочерний элемент.
- Стили: `position:absolute; top:0; left:0; pointer-events:none; z-index:2`.
- Размеры синхронизируем с canvas MapLibre (`m.getCanvas()`), включая обработку `resize`.
- Рисуем:
  ```js
  ctx.strokeStyle = '#00bfff'
  ctx.lineWidth = 3
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'
  ctx.beginPath()
  for (const [[x0, y0], [x1, y1]] of segments) {
    ctx.moveTo(x0, y0)
    ctx.lineTo(x1, y1)
  }
  ctx.stroke()
  ```

### 4. Когда рисовать

- **Есть hover:** `drawSilhouetteOverlay(hoveredAnchor, camera, silhouetteCanvas)`
- **Нет hover:** `ctx.clearRect(0, 0, w, h)`

Вызов — в `render` custom layer, после обновления позиций моделей и raycasting, перед `threeRenderer.render()`.

## Геометрия: indexed и non-indexed

- **Indexed:** `geo.index`, треугольники как тройки индексов; `posAttr` — общий массив вершин.
- **Non-indexed:** треугольники подряд по 3 вершины в `posAttr`.

Нормаль треугольника: `(vC - vB) × (vA - vB)`.

## Файл с реализацией

`frontend/src/App.vue`:
- `getSilhouetteEdges(anchor, camera, width, height)` — возвращает `[[[x0,y0],[x1,y1]], ...]`
- `drawSilhouetteOverlay(anchor, camera, canvas)` — рисует на canvas
- Canvas создаётся в `onAdd` custom layer, привязан к `m.getContainer()` и `m.getCanvas()`.

## Альтернативы (не используем)

- **Inverted hull:** масштабированная копия меша с `BackSide` — даёт «пухлую» обводку.
- **OutlinePass (EffectComposer):** при композитинге с картой модель становилась прозрачной; нужна отдельная отладка.
- **Convex hull в 2D:** сильно упрощает силуэт, теряет детали (ствол, башня).
