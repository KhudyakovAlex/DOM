<template>
  <div class="app">
    <div ref="mapContainer" class="map" />
    <div class="overlay">
      <div class="title">DOM • Карта (PMTiles)</div>
      <div class="controls">
        <button
          class="toggle"
          :class="{ active: !isDark }"
          type="button"
          @click="setDark(false)"
        >
          Светлая
        </button>
        <button
          class="toggle"
          :class="{ active: isDark }"
          type="button"
          @click="setDark(true)"
        >
          Тёмная
        </button>
        <span class="divider" />
        <button
          class="toggle"
          :class="{ active: !is3D }"
          type="button"
          @click="set3D(false)"
        >
          2D
        </button>
        <button
          class="toggle"
          :class="{ active: is3D }"
          type="button"
          @click="set3D(true)"
        >
          3D
        </button>
      </div>
      <div class="status">
        Точки: <b>{{ clickPoints.length }}</b>
        <button class="link" type="button" @click="clearPoints" :disabled="clickPoints.length === 0">
          очистить
        </button>
      </div>
      <div class="status">
        Линии: <b>{{ polylines.length }}</b>
        <span v-if="isDrawingLine" class="muted">рисуем: {{ currentLine.length }} точек</span>
        <span v-if="isSelectMode" class="muted">SHIFT: выделение</span>
        <button class="link" type="button" @click="finishLine" :disabled="!isDrawingLine || currentLine.length < 2">
          закончить
        </button>
        <button class="link" type="button" @click="cancelLine" :disabled="!isDrawingLine">
          отмена
        </button>
        <button class="link" type="button" @click="clearLines" :disabled="polylines.length === 0 && !isDrawingLine">
          очистить
        </button>
      </div>
      <div class="status">
        Модели: <b>{{ models.length }}</b>
        <input class="file" type="file" accept=".glb" @change="onModelFileChange" />
        <button class="link" type="button" @click="uploadModel" :disabled="!modelFile || isUploading">
          {{ isUploading ? 'загрузка...' : 'загрузить .glb' }}
        </button>
        <button class="link" type="button" @click="loadModels" :disabled="isLoadingModels">обновить</button>
        <button class="link" type="button" @click="reloadTank">
          обновить tank
        </button>
        <button class="link" type="button" @click="clearPlacedModels" :disabled="placedModels.length === 0">
          убрать танки ({{ placedModels.length }})
        </button>
      </div>
      <div v-if="modelsError" class="hint">Ошибка моделей: {{ modelsError }}</div>
      <div v-if="models.length" class="models">
        <div v-for="m in models" :key="m.name" class="model-row">
          <a class="model-link" :href="backendBase + m.url" target="_blank" rel="noreferrer">{{ m.name }}</a>
          <span class="muted">{{ Math.round(m.size_bytes / 1024) }} KB</span>
        </div>
      </div>
      <div class="hint">Источник: backend `/api/tiles/yaroslavl.pmtiles`</div>
    </div>

    <div class="toasts" aria-live="polite" aria-atomic="true">
      <div v-for="t in toasts" :key="t.id" class="toast" :class="t.kind">
        <div class="toast-title">{{ t.kind === 'right' ? 'ПКМ' : 'ЛКМ' }} • точка #{{ t.pointId }}</div>
        <div class="toast-body">{{ t.lng }}, {{ t.lat }}</div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { onMounted, onUnmounted, ref } from 'vue'
import maplibregl from 'maplibre-gl'
import 'maplibre-gl/dist/maplibre-gl.css'
import { Protocol } from 'pmtiles'
import * as THREE from 'three'
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js'

const mapContainer = ref(null)
let map = null
const is3D = ref(true)
const isDark = ref(false)
const backendBase = ref('')
const clickPoints = ref([])
let nextPointId = 1
const toasts = ref([])
let nextToastId = 1
const toastTimers = new Map()
const polylines = ref([]) // [{ id, coords: [{lng,lat}, ...], ts }]
let nextLineId = 1
const isDrawingLine = ref(false)
const currentLine = ref([]) // [{lng,lat}, ...]
const isSelectMode = ref(false) // удержание SHIFT
const selectedPointIds = new Set()
const selectedLineIds = new Set()
const models = ref([])
const modelFile = ref(null)
const isUploading = ref(false)
const isLoadingModels = ref(false)
const modelsError = ref('')
const placedModels = ref([]) // [{ id, lng, lat }]
let nextPlacedModelId = 1

let threeLayer = null
let threeScene = null
let threeCamera = null
let threeRenderer = null
let tankTemplate = null
const tankInstances = []
const tankVersion = ref(Date.now())

const TANK_SAND_COLOR = new THREE.Color('#d2b48c') // песочный
const TANK_OUTLINE_COLOR = 0x00bfff // голубой силуэт при наведении
const TANK_OUTLINE_SCALE = 1.04 // толщина обводки (2–4% больше модели)
// Настройка ориентации танка на карте
const TANK_ROT_X = Math.PI / 2 // чтобы модель "стояла" на земле
const TANK_ROT_Y = 0
const TANK_ROT_Z = 0
const TANK_INITIAL_HEADING_RAD = Math.PI // запад
const TANK_SPEED_MPS = 40 / 3.6 // 40 км/ч (в 2 раза быстрее)
const TANK_TURN_RATE_RAD_S = (Math.PI / 2) / 5 // 90° за 5 сек
// Подстройка "куда смотрит" модель (если поедет задом — поставим Math.PI)
const TANK_MODEL_YAW_FIX_RAD = Math.PI
let lastAnimTimeMs = 0

const mouseState = { x: 0, y: 0 }
let hoveredTankAnchor = null
let raycaster = null
const mouseNDC = new THREE.Vector2()

function toMercator(lngLat) {
  const c = maplibregl.MercatorCoordinate.fromLngLat([lngLat.lng, lngLat.lat], 0)
  return {
    x: c.x,
    y: c.y,
    z: c.z,
    scale: c.meterInMercatorCoordinateUnits()
  }
}

const BUILDING_OPACITY_2D = 0.35
const BUILDING_OPACITY_3D = 0.6

const THEMES = {
  light: {
    background: '#f0ede6',
    park: '#98d69e',
    water: '#80d0e8',
    building: '#d9c9a9',
    roads: '#ffffff'
  },
  dark: {
    background: '#0b0f14',
    park: '#1f6a3a',
    water: '#1d3f5a',
    building: '#2b2f36',
    roads: '#9fb2c5'
  }
}

function getTilesUrl() {
  const hostname = window.location.hostname
  if (hostname === 'localhost' || hostname === '127.0.0.1') {
    return 'http://localhost:8000/api/tiles/yaroslavl.pmtiles'
  }
  return `http://${hostname}:8000/api/tiles/yaroslavl.pmtiles`
}

function getBackendBase() {
  const hostname = window.location.hostname
  if (hostname === 'localhost' || hostname === '127.0.0.1') return 'http://localhost:8000'
  return `http://${hostname}:8000`
}

function getBaseStyle(pmtilesHttpUrl, theme) {
  return {
    version: 8,
    name: 'DOM PMTiles',
    sources: {
      pmtiles: {
        type: 'vector',
        url: `pmtiles://${pmtilesHttpUrl}`,
        attribution: '© OpenStreetMap contributors'
      }
    },
    layers: [
      { id: 'background', type: 'background', paint: { 'background-color': theme.background } },
      {
        id: 'park',
        type: 'fill',
        source: 'pmtiles',
        'source-layer': 'park',
        paint: { 'fill-color': theme.park, 'fill-opacity': 0.7 }
      },
      {
        id: 'water',
        type: 'fill',
        source: 'pmtiles',
        'source-layer': 'water',
        paint: { 'fill-color': theme.water, 'fill-opacity': 0.9 }
      },
      {
        id: 'building',
        type: 'fill',
        source: 'pmtiles',
        'source-layer': 'building',
        paint: {
          'fill-color': theme.building,
          'fill-opacity': BUILDING_OPACITY_2D
        }
      },
      {
        id: 'building-3d',
        type: 'fill-extrusion',
        source: 'pmtiles',
        'source-layer': 'building',
        paint: {
          'fill-extrusion-color': theme.building,
          'fill-extrusion-height': ['coalesce', ['get', 'render_height'], 15],
          'fill-extrusion-base': ['coalesce', ['get', 'render_min_height'], 0],
          'fill-extrusion-opacity': BUILDING_OPACITY_3D
        }
      },
      {
        id: 'roads',
        type: 'line',
        source: 'pmtiles',
        'source-layer': 'transportation',
        paint: { 'line-color': theme.roads, 'line-width': 1.2 }
      }
    ]
  }
}

let pmtilesProtocol = null

function ensurePointsLayer() {
  if (!map) return
  if (!map.getSource('click-points')) {
    map.addSource('click-points', {
      type: 'geojson',
      data: {
        type: 'FeatureCollection',
        features: []
      }
    })
  }

  if (!map.getLayer('click-points-layer')) {
    map.addLayer({
      id: 'click-points-layer',
      type: 'circle',
      source: 'click-points',
      paint: {
        'circle-radius': 6,
        'circle-stroke-width': 2,
        'circle-stroke-color': '#0b0f14',
        'circle-color': ['case', ['boolean', ['feature-state', 'selected'], false], '#ffb020', '#4da3ff'],
        'circle-opacity': 0.95
      }
    })
  }
}

function ensureLinesLayer() {
  if (!map) return

  if (!map.getSource('draw-lines')) {
    map.addSource('draw-lines', {
      type: 'geojson',
      data: { type: 'FeatureCollection', features: [] }
    })
  }
  if (!map.getSource('draw-lines-current')) {
    map.addSource('draw-lines-current', {
      type: 'geojson',
      data: { type: 'FeatureCollection', features: [] }
    })
  }

  if (!map.getLayer('draw-lines-layer')) {
    map.addLayer({
      id: 'draw-lines-layer',
      type: 'line',
      source: 'draw-lines',
      paint: {
        'line-color': ['case', ['boolean', ['feature-state', 'selected'], false], '#ffb020', '#ff4d4d'],
        'line-width': 3,
        'line-opacity': 0.9
      }
    })
  }

  // Hitbox слой для попадания курсором (шире линии)
  // Делаем почти прозрачным, но не 0, чтобы гарантированно участвовал в hit-test.
  if (!map.getLayer('draw-lines-hit-layer')) {
    map.addLayer({
      id: 'draw-lines-hit-layer',
      type: 'line',
      source: 'draw-lines',
      paint: {
        'line-color': '#000000',
        'line-width': 14,
        'line-opacity': 0.01
      }
    })
  }

  if (!map.getLayer('draw-lines-current-layer')) {
    map.addLayer({
      id: 'draw-lines-current-layer',
      type: 'line',
      source: 'draw-lines-current',
      paint: {
        'line-color': '#ff4d4d',
        'line-width': 3,
        'line-opacity': 0.75,
        'line-dasharray': [1.2, 1.2]
      }
    })
  }
}

function updatePointsSource() {
  if (!map) return
  const src = map.getSource('click-points')
  if (!src) return

  src.setData({
    type: 'FeatureCollection',
    features: clickPoints.value.map((p) => ({
      type: 'Feature',
      id: p.id,
      properties: { id: p.id, button: p.button },
      geometry: { type: 'Point', coordinates: [p.lng, p.lat] }
    }))
  })

  // re-apply selection after setData (на всякий случай)
  for (const id of selectedPointIds) {
    try {
      map.setFeatureState({ source: 'click-points', id }, { selected: true })
    } catch {
      // ignore
    }
  }
}

function updateLinesSources() {
  if (!map) return

  const srcLines = map.getSource('draw-lines')
  const srcCurrent = map.getSource('draw-lines-current')
  if (!srcLines || !srcCurrent) return

  srcLines.setData({
    type: 'FeatureCollection',
    features: polylines.value.map((l) => ({
      type: 'Feature',
      id: l.id,
      properties: { id: l.id },
      geometry: {
        type: 'LineString',
        coordinates: l.coords.map((c) => [c.lng, c.lat])
      }
    }))
  })

  // re-apply selection after setData
  for (const id of selectedLineIds) {
    try {
      map.setFeatureState({ source: 'draw-lines', id }, { selected: true })
    } catch {
      // ignore
    }
  }

  if (isDrawingLine.value && currentLine.value.length >= 2) {
    srcCurrent.setData({
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          id: 'current',
          properties: {},
          geometry: {
            type: 'LineString',
            coordinates: currentLine.value.map((c) => [c.lng, c.lat])
          }
        }
      ]
    })
  } else {
    srcCurrent.setData({ type: 'FeatureCollection', features: [] })
  }
}

function addPoint(button, lngLat) {
  const pointId = nextPointId++
  clickPoints.value.push({
    id: pointId,
    button, // 'left' | 'right'
    lng: lngLat.lng,
    lat: lngLat.lat,
    ts: Date.now()
  })
  updatePointsSource()

  // Toast с координатами (исчезает сам)
  const toastId = nextToastId++
  const toast = {
    id: toastId,
    kind: button, // 'left' | 'right'
    pointId,
    lng: lngLat.lng.toFixed(6),
    lat: lngLat.lat.toFixed(6)
  }
  toasts.value.unshift(toast)

  const timer = setTimeout(() => {
    toasts.value = toasts.value.filter((t) => t.id !== toastId)
    toastTimers.delete(toastId)
  }, 2500)
  toastTimers.set(toastId, timer)
}

function addLineVertex(lngLat) {
  // Если есть танк и уже есть 1-я точка (после постановки) — это траектория танка
  if (tankInstances.length > 0 && isDrawingLine.value && currentLine.value.length >= 1) {
    pushTrajectoryPoint(lngLat)
  } else {
    if (!isDrawingLine.value) {
      isDrawingLine.value = true
      currentLine.value = []
    }
    currentLine.value.push({ lng: lngLat.lng, lat: lngLat.lat })
    updateLinesSources()
  }

  const toastId = nextToastId++
  const toast = {
    id: toastId,
    kind: 'right',
    pointId: currentLine.value.length,
    lng: lngLat.lng.toFixed(6),
    lat: lngLat.lat.toFixed(6)
  }
  toasts.value.unshift(toast)
  const timer = setTimeout(() => {
    toasts.value = toasts.value.filter((t) => t.id !== toastId)
    toastTimers.delete(toastId)
  }, 2000)
  toastTimers.set(toastId, timer)
}

function clearPoints() {
  clickPoints.value = []
  // clear selection state
  for (const id of selectedPointIds) {
    try {
      map?.setFeatureState({ source: 'click-points', id }, { selected: false })
    } catch {
      // ignore
    }
  }
  selectedPointIds.clear()
  updatePointsSource()
}

function finishLine() {
  if (!isDrawingLine.value) return
  if (currentLine.value.length < 2) return

  const lineId = nextLineId++
  polylines.value.push({
    id: lineId,
    coords: currentLine.value.slice(),
    ts: Date.now()
  })
  isDrawingLine.value = false
  currentLine.value = []
  updateLinesSources()
}

function cancelLine() {
  if (!isDrawingLine.value) return
  isDrawingLine.value = false
  currentLine.value = []
  updateLinesSources()
}

function clearLines() {
  polylines.value = []
  isDrawingLine.value = false
  currentLine.value = []
  for (const id of selectedLineIds) {
    try {
      map?.setFeatureState({ source: 'draw-lines', id }, { selected: false })
    } catch {
      // ignore
    }
  }
  selectedLineIds.clear()
  updateLinesSources()
}

function clearPlacedModels() {
  placedModels.value = []
  tankInstances.length = 0
  hoveredTankAnchor = null
  if (threeScene) {
    // оставим только свет (первые 2 объекта)
    while (threeScene.children.length > 2) {
      threeScene.remove(threeScene.children[2])
    }
  }
  if (map) map.triggerRepaint()
}

function addOutlineToTank(anchor) {
  anchor.traverse((child) => {
    if (!child.isMesh || !child.geometry || child.userData.__isOutline) return
    const outline = new THREE.Mesh(
      child.geometry,
      new THREE.MeshBasicMaterial({
        color: TANK_OUTLINE_COLOR,
        side: THREE.BackSide,
        depthWrite: false
      })
    )
    outline.scale.setScalar(TANK_OUTLINE_SCALE)
    outline.visible = false
    outline.renderOrder = -1
    outline.userData.__isOutline = true
    outline.userData.__tankAnchor = anchor
    child.add(outline)
    child.userData.__outlineMesh = outline
    child.userData.__tankAnchor = anchor
  })
}

function addTankAt(lngLat) {
  const id = nextPlacedModelId++
  placedModels.value.push({ id, lng: lngLat.lng, lat: lngLat.lat })

  if (!tankTemplate || !threeScene || !map) return

  const coord = toMercator(lngLat)

  // Иерархия чтобы yaw был вокруг вертикальной оси через центр
  const anchor = new THREE.Group()
  const yaw = new THREE.Group()   // вращение вокруг мировой вертикали (Z)
  const align = new THREE.Group() // "укладка" glTF (Y-up) на карту

  yaw.rotation.z = TANK_INITIAL_HEADING_RAD + TANK_MODEL_YAW_FIX_RAD
  align.rotation.set(TANK_ROT_X, TANK_ROT_Y, TANK_ROT_Z)
  align.add(tankTemplate.clone(true))
  yaw.add(align)
  anchor.add(yaw)

  // Позиция/scale считаются в render() относительно центра карты (как в примере),
  // чтобы убрать дрожание из-за огромных mercator координат.
  anchor.userData.__x = coord.x
  anchor.userData.__y = coord.y
  anchor.userData.__z = coord.z
  anchor.userData.__scale = coord.scale
  anchor.userData.__heading = TANK_INITIAL_HEADING_RAD
  anchor.userData.__waypoints = [] // [{x,y,z,scale}]
  anchor.userData.__targetIdx = null
  anchor.userData.__state = 'idle' // idle | turning | moving
  anchor.userData.__placedId = id
  anchor.userData.__yaw = yaw

  addOutlineToTank(anchor)
  threeScene.add(anchor)
  tankInstances.push(anchor)
  map.triggerRepaint()
}

function startTrajectoryAt(lngLat) {
  // начинаем рисование ломаной с первой точки
  isDrawingLine.value = true
  currentLine.value = [{ lng: lngLat.lng, lat: lngLat.lat }]
  updateLinesSources()

  const tank = tankInstances[tankInstances.length - 1]
  if (!tank || !map) return
  tank.userData.__waypoints = [toMercator(lngLat)]
  tank.userData.__targetIdx = null
  tank.userData.__state = 'idle'
}

function pushTrajectoryPoint(lngLat) {
  currentLine.value.push({ lng: lngLat.lng, lat: lngLat.lat })
  updateLinesSources()

  const tank = tankInstances[tankInstances.length - 1]
  if (!tank || !map) return
  tank.userData.__waypoints.push(toMercator(lngLat))

  // если это первая "целевая" точка (вторая вершина) — запускаем поворот/движение
  if (tank.userData.__state === 'idle' && tank.userData.__waypoints.length >= 2) {
    tank.userData.__targetIdx = 1
    tank.userData.__state = 'turning'
  }
}

function normalizeAngle(a) {
  let x = a
  while (x <= -Math.PI) x += Math.PI * 2
  while (x > Math.PI) x -= Math.PI * 2
  return x
}

function stepAngle(current, target, maxStep) {
  const diff = normalizeAngle(target - current)
  if (Math.abs(diff) <= maxStep) return target
  return current + Math.sign(diff) * maxStep
}

function tintTankToSand(root) {
  root.traverse((child) => {
    if (!child.isMesh) return

    const apply = (mat) => {
      if (!mat) return mat
      const m = mat.clone ? mat.clone() : mat
      if (m.color) m.color = TANK_SAND_COLOR.clone()
      if ('metalness' in m) m.metalness = 0.05
      if ('roughness' in m) m.roughness = 0.95
      m.needsUpdate = true
      return m
    }

    if (Array.isArray(child.material)) child.material = child.material.map(apply)
    else child.material = apply(child.material)
  })
}

function reloadTank() {
  tankVersion.value = Date.now()
  tankTemplate = null
  // пересоберём все танки после загрузки
  const existing = placedModels.value.slice()
  clearPlacedModels()
  placedModels.value = existing

  // если слой ещё не поднят — поднимем, загрузка пойдёт в onAdd
  if (!threeLayer && map) ensureThreeLayer()
  if (map) map.triggerRepaint()
}

function ensureThreeLayer() {
  if (!map || threeLayer) return

  threeLayer = {
    id: 'tank-3d-layer',
    type: 'custom',
    renderingMode: '3d',
    onAdd: function (m, gl) {
      raycaster = new THREE.Raycaster()
      threeCamera = new THREE.Camera()
      threeScene = new THREE.Scene()

      m.on('mousemove', (e) => {
        mouseState.x = e.point.x
        mouseState.y = e.point.y
      })

      const ambient = new THREE.AmbientLight(0xffffff, 0.9)
      const dir = new THREE.DirectionalLight(0xffffff, 0.6)
      dir.position.set(1, 1, 2)
      threeScene.add(ambient)
      threeScene.add(dir)

      threeRenderer = new THREE.WebGLRenderer({
        canvas: m.getCanvas(),
        context: gl,
        antialias: true,
        logarithmicDepthBuffer: true
      })
      threeRenderer.autoClear = false

      const loader = new GLTFLoader()
      const url = `${backendBase.value}/models/tank.glb?v=${tankVersion.value}`
      loader.load(
        url,
        (gltf) => {
          const raw = gltf.scene
          tintTankToSand(raw)

          // Нормализуем pivot модели:
          // - центр по X/Z в (0,0)
          // - низ по Y в 0 (glTF обычно Y-up)
          const box = new THREE.Box3().setFromObject(raw)
          const center = box.getCenter(new THREE.Vector3())
          const minY = box.min.y
          raw.position.set(-center.x, -minY, -center.z)

          tankTemplate = new THREE.Group()
          tankTemplate.add(raw)
          // Ставим уже добавленные точки (если были клики до загрузки модели)
          const existing = placedModels.value.slice()
          placedModels.value = []
          for (const p of existing) {
            addTankAt({ lng: p.lng, lat: p.lat })
          }
          m.triggerRepaint()
        },
        undefined,
        () => {
          // ignore load errors here
        }
      )
    },
    render: function (gl, matrix) {
      if (!threeRenderer || !threeScene || !threeCamera) return
      if (!is3D.value) return

      const now = performance.now()
      if (!lastAnimTimeMs) lastAnimTimeMs = now
      let dt = (now - lastAnimTimeMs) / 1000
      lastAnimTimeMs = now
      // clamp, чтобы при сворачивании окна не "телепортировались"
      dt = Math.min(dt, 0.05)

      const mtx = Array.isArray(matrix)
        ? matrix
        : matrix?.defaultProjectionData?.mainMatrix || matrix?.mainMatrix || matrix
      if (!mtx) return

      // Приём из примера: cameraMatrix * translation(centerCoord),
      // а сами модели — в координатах относительно centerCoord.
      const center = maplibregl.MercatorCoordinate.fromLngLat(
        [map.getCenter().lng, map.getCenter().lat],
        0
      )
      const m = new THREE.Matrix4().fromArray(mtx)
      const l = new THREE.Matrix4().makeTranslation(center.x, center.y, center.z)
      threeCamera.projectionMatrix = m.multiply(l)

      for (const obj of tankInstances) {
        const waypoints = obj.userData.__waypoints
        const targetIdx = obj.userData.__targetIdx
        const state = obj.userData.__state
        const scale = obj.userData.__scale
        const yaw = obj.userData.__yaw
        if (!scale) continue

        if (state === 'turning' && targetIdx !== null && waypoints?.[targetIdx]) {
          const t = waypoints[targetIdx]
          const dx = t.x - obj.userData.__x
          const dy = t.y - obj.userData.__y
          const desired = Math.atan2(dy, dx)
          obj.userData.__heading = stepAngle(obj.userData.__heading, desired, TANK_TURN_RATE_RAD_S * dt)

          if (Math.abs(normalizeAngle(desired - obj.userData.__heading)) < 0.02) {
            obj.userData.__heading = desired
            obj.userData.__state = 'moving'
          }
        } else if (state === 'moving' && targetIdx !== null && waypoints?.[targetIdx]) {
          const t = waypoints[targetIdx]
          const dx = t.x - obj.userData.__x
          const dy = t.y - obj.userData.__y
          const dist = Math.hypot(dx, dy)
          const step = TANK_SPEED_MPS * dt * scale

          if (dist <= step || dist < 1e-12) {
            obj.userData.__x = t.x
            obj.userData.__y = t.y
            obj.userData.__z = t.z
            // следующая цель?
            if (targetIdx + 1 < waypoints.length) {
              obj.userData.__targetIdx = targetIdx + 1
              obj.userData.__state = 'turning'
            } else {
              obj.userData.__state = 'idle'
              obj.userData.__targetIdx = null
            }
          } else {
            const ux = dx / dist
            const uy = dy / dist
            obj.userData.__x += ux * step
            obj.userData.__y += uy * step
            obj.userData.__heading = Math.atan2(uy, ux)
          }
        }

        // yaw вокруг вертикальной оси через центр
        if (yaw) yaw.rotation.z = (obj.userData.__heading ?? 0) + TANK_MODEL_YAW_FIX_RAD

        obj.position.set(
          obj.userData.__x - center.x,
          obj.userData.__y - center.y,
          (obj.userData.__z - center.z)
        )
        obj.scale.set(scale, scale, scale)
      }

      // Raycasting: наведение на танк → обводка
      if (raycaster && tankInstances.length > 0) {
        const canvas = map.getCanvas()
        const t = map.transform
        const w = (t?.width ?? canvas.getBoundingClientRect().width) || 1
        const h = (t?.height ?? canvas.getBoundingClientRect().height) || 1
        mouseNDC.x = (mouseState.x / w) * 2 - 1
        mouseNDC.y = 1 - (mouseState.y / h) * 2

        // Луч через unproject near/far (THREE.Camera без position)
        const invProj = new THREE.Matrix4().copy(threeCamera.projectionMatrix).invert()
        const nearPt = new THREE.Vector3(mouseNDC.x, mouseNDC.y, -1).applyMatrix4(invProj)
        const farPt = new THREE.Vector3(mouseNDC.x, mouseNDC.y, 1).applyMatrix4(invProj)
        const dir = farPt.clone().sub(nearPt).normalize()
        raycaster.ray.set(nearPt, dir)

        const meshes = []
        tankInstances.forEach((a) => a.traverse((c) => { if (c.isMesh && !c.userData.__isOutline) meshes.push(c) }))
        const hits = raycaster.intersectObjects(meshes, false)

        let nextHovered = null
        if (hits.length > 0) {
          const hit = hits[0]
          nextHovered = hit.object.userData.__tankAnchor || null
        }

        if (nextHovered !== hoveredTankAnchor) {
          tankInstances.forEach((anchor) => {
            anchor.traverse((c) => {
              if (c.userData.__outlineMesh) c.userData.__outlineMesh.visible = anchor === nextHovered
            })
          })
          hoveredTankAnchor = nextHovered
        }
        canvas.style.cursor = isSelectMode.value ? 'default' : (nextHovered ? 'pointer' : '')
      }

      threeRenderer.resetState()
      threeRenderer.render(threeScene, threeCamera)

      // просим перерисовку для анимации
      if (tankInstances.length > 0) map.triggerRepaint()
    }
  }

  map.addLayer(threeLayer)
}

function onModelFileChange(e) {
  const f = e.target?.files?.[0] || null
  modelFile.value = f
}

async function loadModels() {
  modelsError.value = ''
  isLoadingModels.value = true
  try {
    const res = await fetch(`${backendBase.value}/api/models`)
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const data = await res.json()
    models.value = data.items || []
  } catch (err) {
    modelsError.value = String(err?.message || err)
  } finally {
    isLoadingModels.value = false
  }
}

async function uploadModel() {
  if (!modelFile.value) return
  modelsError.value = ''
  isUploading.value = true
  try {
    const fd = new FormData()
    fd.append('file', modelFile.value)
    const res = await fetch(`${backendBase.value}/api/models/upload`, {
      method: 'POST',
      body: fd
    })
    if (!res.ok) {
      const txt = await res.text().catch(() => '')
      throw new Error(txt || `HTTP ${res.status}`)
    }
    modelFile.value = null
    await loadModels()
  } catch (err) {
    modelsError.value = String(err?.message || err)
  } finally {
    isUploading.value = false
  }
}

function apply3DMode() {
  if (!map) return

  const building2D = map.getLayer('building') ? 'building' : null
  const building3D = map.getLayer('building-3d') ? 'building-3d' : null

  if (building2D) {
    map.setLayoutProperty(building2D, 'visibility', is3D.value ? 'none' : 'visible')
  }
  if (building3D) {
    map.setLayoutProperty(building3D, 'visibility', is3D.value ? 'visible' : 'none')
  }

  if (is3D.value) {
    const z = map.getZoom()
    map.easeTo({
      pitch: 55,
      zoom: z < 12 ? 12 : z,
      duration: 500
    })
  } else {
    map.easeTo({ pitch: 0, duration: 400 })
  }
}

function set3D(value) {
  is3D.value = value
  apply3DMode()
}

function applyTheme() {
  if (!map) return
  const t = isDark.value ? THEMES.dark : THEMES.light

  if (map.getLayer('background')) {
    map.setPaintProperty('background', 'background-color', t.background)
  }
  if (map.getLayer('park')) {
    map.setPaintProperty('park', 'fill-color', t.park)
  }
  if (map.getLayer('water')) {
    map.setPaintProperty('water', 'fill-color', t.water)
  }
  if (map.getLayer('roads')) {
    map.setPaintProperty('roads', 'line-color', t.roads)
  }
  if (map.getLayer('building')) {
    map.setPaintProperty('building', 'fill-color', t.building)
    map.setPaintProperty('building', 'fill-opacity', BUILDING_OPACITY_2D)
  }
  if (map.getLayer('building-3d')) {
    map.setPaintProperty('building-3d', 'fill-extrusion-color', t.building)
    map.setPaintProperty('building-3d', 'fill-extrusion-opacity', BUILDING_OPACITY_3D)
  }
}

function setDark(value) {
  isDark.value = value
  applyTheme()
}

function applyCursorMode() {
  if (!map) return
  // "стрелка" при удержании SHIFT
  map.getCanvas().style.cursor = isSelectMode.value ? 'default' : ''
}

function distPointToSegmentSq(p, a, b) {
  // p, a, b: {x,y} in pixels
  const abx = b.x - a.x
  const aby = b.y - a.y
  const apx = p.x - a.x
  const apy = p.y - a.y
  const abLenSq = abx * abx + aby * aby
  if (abLenSq === 0) {
    return apx * apx + apy * apy
  }
  let t = (apx * abx + apy * aby) / abLenSq
  t = Math.max(0, Math.min(1, t))
  const cx = a.x + abx * t
  const cy = a.y + aby * t
  const dx = p.x - cx
  const dy = p.y - cy
  return dx * dx + dy * dy
}

function toggleSelectionAtEvent(e) {
  if (!map) return

  // 1) Быстрый путь: попробуем получить фичи напрямую из рендера
  const features = map.queryRenderedFeatures(e.point, {
    layers: ['click-points-layer', 'draw-lines-hit-layer', 'draw-lines-layer']
  })
  if (features && features.length > 0) {
    const f = features[0]
    if (f.layer.id === 'click-points-layer') {
      const id = f.id ?? f.properties?.id
      if (id === undefined || id === null) return
      const key = Number(id)
      const isSelected = selectedPointIds.has(key)
      selectedPointIds[isSelected ? 'delete' : 'add'](key)
      map.setFeatureState({ source: 'click-points', id: key }, { selected: !isSelected })
      return
    }

    if (f.layer.id === 'draw-lines-layer' || f.layer.id === 'draw-lines-hit-layer') {
      const id = f.id ?? f.properties?.id
      if (id === undefined || id === null) return
      const key = Number(id)
      const isSelected = selectedLineIds.has(key)
      selectedLineIds[isSelected ? 'delete' : 'add'](key)
      map.setFeatureState({ source: 'draw-lines', id: key }, { selected: !isSelected })
      return
    }
  }

  // 2) Надёжный путь: вручную выбираем ближайший объект в окрестности
  const hitRadiusPx = 10
  const hitRadiusSq = hitRadiusPx * hitRadiusPx

  // ближайшая точка
  let bestPointId = null
  let bestPointDistSq = Infinity
  for (const p of clickPoints.value) {
    let sp
    try {
      sp = map.project([p.lng, p.lat])
    } catch {
      continue
    }
    const dx = e.point.x - sp.x
    const dy = e.point.y - sp.y
    const d2 = dx * dx + dy * dy
    if (d2 < bestPointDistSq) {
      bestPointDistSq = d2
      bestPointId = p.id
    }
  }

  // ближайшая линия
  let bestLineId = null
  let bestLineDistSq = Infinity
  for (const l of polylines.value) {
    const coords = l.coords
    if (!coords || coords.length < 2) continue
    let prev
    try {
      prev = map.project([coords[0].lng, coords[0].lat])
    } catch {
      continue
    }
    for (let i = 1; i < coords.length; i++) {
      let curr
      try {
        curr = map.project([coords[i].lng, coords[i].lat])
      } catch {
        continue
      }
      const d2 = distPointToSegmentSq(e.point, prev, curr)
      if (d2 < bestLineDistSq) {
        bestLineDistSq = d2
        bestLineId = l.id
      }
      prev = curr
    }
  }

  const pointHit = bestPointId !== null && bestPointDistSq <= hitRadiusSq
  const lineHit = bestLineId !== null && bestLineDistSq <= hitRadiusSq
  if (!pointHit && !lineHit) return

  // выбираем ближайшее
  if (pointHit && (!lineHit || bestPointDistSq <= bestLineDistSq)) {
    const key = Number(bestPointId)
    const isSelected = selectedPointIds.has(key)
    selectedPointIds[isSelected ? 'delete' : 'add'](key)
    map.setFeatureState({ source: 'click-points', id: key }, { selected: !isSelected })
    return
  }

  const key = Number(bestLineId)
  const isSelected = selectedLineIds.has(key)
  selectedLineIds[isSelected ? 'delete' : 'add'](key)
  map.setFeatureState({ source: 'draw-lines', id: key }, { selected: !isSelected })
}

onMounted(() => {
  backendBase.value = getBackendBase()
  const tilesUrl = getTilesUrl()

  pmtilesProtocol = new Protocol()
  maplibregl.addProtocol('pmtiles', pmtilesProtocol.tile)

  map = new maplibregl.Map({
    container: mapContainer.value,
    style: getBaseStyle(tilesUrl, isDark.value ? THEMES.dark : THEMES.light),
    center: [39.8915, 57.6261], // Ярославль (примерно)
    zoom: 11,
    pitch: 55,
    antialias: true
  })

  map.addControl(new maplibregl.NavigationControl(), 'top-right')

  const onLeftClick = (e) => {
    if (isSelectMode.value) {
      toggleSelectionAtEvent(e)
      return
    }
    // Новый танк — новая траектория
    clearPlacedModels()
    addTankAt(e.lngLat)
    startTrajectoryAt(e.lngLat)
  }
  const onRightClick = (e) => {
    // чтобы не всплывало стандартное меню браузера
    e.preventDefault()
    if (isSelectMode.value) {
      toggleSelectionAtEvent(e)
      return
    }
    addLineVertex(e.lngLat)
  }

  map.once('load', () => {
    apply3DMode()
    applyTheme()
    ensurePointsLayer()
    updatePointsSource()
    ensureLinesLayer()
    updateLinesSources()
    loadModels()
    ensureThreeLayer()

    map.on('click', onLeftClick)
    map.on('contextmenu', onRightClick)

    // SHIFT selection mode
    const onKeyDown = (ev) => {
      if (ev.key !== 'Shift') return
      if (!isSelectMode.value) {
        isSelectMode.value = true
        applyCursorMode()
      }
    }
    const onKeyUp = (ev) => {
      if (ev.key !== 'Shift') return
      if (isSelectMode.value) {
        isSelectMode.value = false
        applyCursorMode()
      }
    }
    const onBlur = () => {
      if (isSelectMode.value) {
        isSelectMode.value = false
        applyCursorMode()
      }
    }

    window.addEventListener('keydown', onKeyDown)
    window.addEventListener('keyup', onKeyUp)
    window.addEventListener('blur', onBlur)

    map.__domHandlers = { ...map.__domHandlers, onKeyDown, onKeyUp, onBlur }
    applyCursorMode()
  })

  // сохраним обработчики, чтобы снять в onUnmounted
  map.__domHandlers = { onLeftClick, onRightClick }
})

onUnmounted(() => {
  if (map) {
    if (map.__domHandlers) {
      map.off('click', map.__domHandlers.onLeftClick)
      map.off('contextmenu', map.__domHandlers.onRightClick)
      if (map.__domHandlers.onKeyDown) window.removeEventListener('keydown', map.__domHandlers.onKeyDown)
      if (map.__domHandlers.onKeyUp) window.removeEventListener('keyup', map.__domHandlers.onKeyUp)
      if (map.__domHandlers.onBlur) window.removeEventListener('blur', map.__domHandlers.onBlur)
    }
    map.remove()
    map = null
  }

  // Cleanup toasts timers
  toastTimers.forEach((timer) => clearTimeout(timer))
  toastTimers.clear()

  try {
    maplibregl.removeProtocol('pmtiles')
  } catch {
    // ignore
  }
  pmtilesProtocol = null
})
</script>

<style>
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', sans-serif;
  background: #0b0f14;
}

.app {
  min-height: 100vh;
  position: relative;
}

.map {
  position: absolute;
  inset: 0;
}

.overlay {
  position: absolute;
  left: 12px;
  top: 12px;
  padding: 10px 12px;
  border-radius: 10px;
  background: rgba(11, 15, 20, 0.72);
  border: 1px solid rgba(255, 255, 255, 0.12);
  color: rgba(255, 255, 255, 0.92);
  backdrop-filter: blur(8px);
  max-width: 520px;
}

.controls {
  display: flex;
  gap: 8px;
  margin: 6px 0 10px;
  align-items: center;
}

.divider {
  width: 1px;
  height: 18px;
  background: rgba(255, 255, 255, 0.18);
  margin: 0 2px;
  border-radius: 1px;
}

.toggle {
  appearance: none;
  border: 1px solid rgba(255, 255, 255, 0.18);
  background: rgba(255, 255, 255, 0.08);
  color: rgba(255, 255, 255, 0.92);
  padding: 6px 10px;
  border-radius: 10px;
  cursor: pointer;
  font-weight: 600;
  font-size: 12px;
  line-height: 1;
}

.toggle.active {
  background: rgba(255, 255, 255, 0.18);
  border-color: rgba(255, 255, 255, 0.28);
}

.status {
  font-size: 12px;
  opacity: 0.92;
  display: flex;
  gap: 8px;
  align-items: baseline;
  margin: 2px 0 6px;
}

.muted {
  opacity: 0.75;
}

.file {
  max-width: 220px;
  font-size: 12px;
}

.models {
  margin: 6px 0 2px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.model-row {
  display: flex;
  gap: 8px;
  justify-content: space-between;
}

.model-link {
  color: rgba(255, 255, 255, 0.92);
  text-decoration: underline;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 360px;
}

.link {
  appearance: none;
  border: 0;
  background: transparent;
  color: rgba(255, 255, 255, 0.9);
  text-decoration: underline;
  cursor: pointer;
  padding: 0;
  font-size: 12px;
}

.link:disabled {
  opacity: 0.4;
  cursor: default;
  text-decoration: none;
}

.title {
  font-weight: 700;
  letter-spacing: 0.2px;
  margin-bottom: 4px;
}

.hint {
  font-size: 12px;
  opacity: 0.85;
}

.toasts {
  position: absolute;
  right: 12px;
  bottom: 12px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  align-items: flex-end;
  pointer-events: none;
}

.toast {
  pointer-events: none;
  width: 260px;
  padding: 10px 12px;
  border-radius: 12px;
  background: rgba(11, 15, 20, 0.78);
  border: 1px solid rgba(255, 255, 255, 0.12);
  color: rgba(255, 255, 255, 0.92);
  backdrop-filter: blur(10px);
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.35);
  animation: toast-in-out 2.5s ease-in-out forwards;
}

.toast.left {
  border-left: 4px solid #4da3ff;
}

.toast.right {
  border-left: 4px solid #ffb020;
}

.toast-title {
  font-size: 12px;
  font-weight: 700;
  margin-bottom: 4px;
}

.toast-body {
  font-size: 12px;
  opacity: 0.9;
  font-variant-numeric: tabular-nums;
}

@keyframes toast-in-out {
  0% {
    transform: translateY(8px);
    opacity: 0;
  }
  10% {
    transform: translateY(0);
    opacity: 1;
  }
  80% {
    transform: translateY(0);
    opacity: 1;
  }
  100% {
    transform: translateY(0);
    opacity: 0;
  }
}
</style>
