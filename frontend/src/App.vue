<template>
  <div class="app">
    <div ref="mapContainer" class="map" />
    <div class="overlay">
      <div class="title">DOM • Карта (PMTiles)</div>
      <div class="hint">Источник: backend `/api/tiles/yaroslavl.pmtiles`</div>
    </div>
  </div>
</template>

<script setup>
import { onMounted, onUnmounted, ref } from 'vue'
import maplibregl from 'maplibre-gl'
import 'maplibre-gl/dist/maplibre-gl.css'
import { Protocol } from 'pmtiles'

const mapContainer = ref(null)
let map = null

function getTilesUrl() {
  const hostname = window.location.hostname
  if (hostname === 'localhost' || hostname === '127.0.0.1') {
    return 'http://localhost:8000/api/tiles/yaroslavl.pmtiles'
  }
  return `http://${hostname}:8000/api/tiles/yaroslavl.pmtiles`
}

function getBaseStyle(pmtilesHttpUrl) {
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
      { id: 'background', type: 'background', paint: { 'background-color': '#f0ede6' } },
      {
        id: 'park',
        type: 'fill',
        source: 'pmtiles',
        'source-layer': 'park',
        paint: { 'fill-color': '#98d69e', 'fill-opacity': 0.7 }
      },
      {
        id: 'water',
        type: 'fill',
        source: 'pmtiles',
        'source-layer': 'water',
        paint: { 'fill-color': '#80d0e8', 'fill-opacity': 0.9 }
      },
      {
        id: 'building',
        type: 'fill',
        source: 'pmtiles',
        'source-layer': 'building',
        paint: { 'fill-color': '#d9c9a9', 'fill-opacity': 0.8 }
      },
      {
        id: 'roads',
        type: 'line',
        source: 'pmtiles',
        'source-layer': 'transportation',
        paint: { 'line-color': '#ffffff', 'line-width': 1.2 }
      }
    ]
  }
}

let pmtilesProtocol = null

onMounted(() => {
  const tilesUrl = getTilesUrl()

  pmtilesProtocol = new Protocol()
  maplibregl.addProtocol('pmtiles', pmtilesProtocol.tile)

  map = new maplibregl.Map({
    container: mapContainer.value,
    style: getBaseStyle(tilesUrl),
    center: [39.8915, 57.6261], // Ярославль (примерно)
    zoom: 11
  })

  map.addControl(new maplibregl.NavigationControl(), 'top-right')
})

onUnmounted(() => {
  if (map) {
    map.remove()
    map = null
  }
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

.title {
  font-weight: 700;
  letter-spacing: 0.2px;
  margin-bottom: 4px;
}

.hint {
  font-size: 12px;
  opacity: 0.85;
}
</style>
