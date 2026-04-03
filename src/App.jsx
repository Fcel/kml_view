import { useState, useCallback, useRef } from 'react'
import { useJsApiLoader, GoogleMap, Polygon, Polyline, Marker, InfoWindow } from '@react-google-maps/api'
import { kml } from '@tmcw/togeojson'
import './App.css'

const LIBRARIES = ['places']

const MAP_OPTIONS = {
  mapTypeId: 'satellite',
  mapTypeControl: true,
  streetViewControl: false,
  fullscreenControl: true,
  zoomControl: true,
  tilt: 0,
}

const DEFAULT_CENTER = { lat: 39.0, lng: 35.0 }
const DEFAULT_ZOOM = 6

function parseKmlColor(colorStr) {
  if (!colorStr || colorStr.length < 6) return null
  // KML color format: aabbggrr
  if (colorStr.length === 8) {
    const a = parseInt(colorStr.slice(0, 2), 16) / 255
    const b = parseInt(colorStr.slice(2, 4), 16)
    const g = parseInt(colorStr.slice(4, 6), 16)
    const r = parseInt(colorStr.slice(6, 8), 16)
    return { hex: `rgb(${r},${g},${b})`, opacity: a }
  }
  return { hex: colorStr, opacity: 1 }
}

function getFeatureStyle(feature) {
  const style = feature.properties?.style || {}
  const lineStyle = style.LineStyle || {}
  const polyStyle = style.PolyStyle || {}

  const strokeColor = parseKmlColor(lineStyle.color)
  const fillColor = parseKmlColor(polyStyle.color)

  return {
    strokeColor: strokeColor?.hex || '#FF4444',
    strokeOpacity: strokeColor?.opacity ?? 0.9,
    strokeWeight: parseFloat(lineStyle.width) || 2,
    fillColor: fillColor?.hex || '#FF4444',
    fillOpacity: fillColor?.opacity ?? 0.35,
  }
}

function coordsToLatLng(coordinates) {
  if (!coordinates) return []
  return coordinates.map(([lng, lat]) => ({ lat, lng }))
}

function Feature({ feature, onClick }) {
  const style = getFeatureStyle(feature)
  const geom = feature.geometry
  if (!geom) return null

  const handleClick = () => onClick(feature)

  if (geom.type === 'Point') {
    const [lng, lat] = geom.coordinates
    return <Marker position={{ lat, lng }} onClick={handleClick} />
  }

  if (geom.type === 'LineString') {
    return (
      <Polyline
        path={coordsToLatLng(geom.coordinates)}
        options={{ strokeColor: style.strokeColor, strokeOpacity: style.strokeOpacity, strokeWeight: style.strokeWeight }}
        onClick={handleClick}
      />
    )
  }

  if (geom.type === 'MultiLineString') {
    return geom.coordinates.map((line, i) => (
      <Polyline
        key={i}
        path={coordsToLatLng(line)}
        options={{ strokeColor: style.strokeColor, strokeOpacity: style.strokeOpacity, strokeWeight: style.strokeWeight }}
        onClick={handleClick}
      />
    ))
  }

  if (geom.type === 'Polygon') {
    return (
      <Polygon
        paths={geom.coordinates.map(ring => coordsToLatLng(ring))}
        options={{
          strokeColor: style.strokeColor,
          strokeOpacity: style.strokeOpacity,
          strokeWeight: style.strokeWeight,
          fillColor: style.fillColor,
          fillOpacity: style.fillOpacity,
        }}
        onClick={handleClick}
      />
    )
  }

  if (geom.type === 'MultiPolygon') {
    return geom.coordinates.map((poly, i) => (
      <Polygon
        key={i}
        paths={poly.map(ring => coordsToLatLng(ring))}
        options={{
          strokeColor: style.strokeColor,
          strokeOpacity: style.strokeOpacity,
          strokeWeight: style.strokeWeight,
          fillColor: style.fillColor,
          fillOpacity: style.fillOpacity,
        }}
        onClick={handleClick}
      />
    ))
  }

  if (geom.type === 'GeometryCollection') {
    return geom.geometries.map((subGeom, i) => (
      <Feature key={i} feature={{ ...feature, geometry: subGeom }} onClick={onClick} />
    ))
  }

  return null
}

function getFeatureCenter(feature) {
  const geom = feature.geometry
  if (!geom) return null
  if (geom.type === 'Point') {
    const [lng, lat] = geom.coordinates
    return { lat, lng }
  }
  if (geom.type === 'LineString' && geom.coordinates.length > 0) {
    const mid = Math.floor(geom.coordinates.length / 2)
    const [lng, lat] = geom.coordinates[mid]
    return { lat, lng }
  }
  if (geom.type === 'Polygon' && geom.coordinates[0]?.length > 0) {
    const ring = geom.coordinates[0]
    const [lng, lat] = ring[Math.floor(ring.length / 2)]
    return { lat, lng }
  }
  if (geom.type === 'MultiPolygon' && geom.coordinates[0]?.[0]?.length > 0) {
    const ring = geom.coordinates[0][0]
    const [lng, lat] = ring[Math.floor(ring.length / 2)]
    return { lat, lng }
  }
  return null
}

export default function App() {
  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY || ''
  const { isLoaded, loadError } = useJsApiLoader({ googleMapsApiKey: apiKey, libraries: LIBRARIES })

  const [features, setFeatures] = useState([])
  const [fileName, setFileName] = useState('')
  const [selected, setSelected] = useState(null)
  const [error, setError] = useState('')
  const [isDragging, setIsDragging] = useState(false)
  const mapRef = useRef(null)

  const onMapLoad = useCallback((map) => { mapRef.current = map }, [])

  const fitBoundsToFeatures = useCallback((featureList) => {
    if (!mapRef.current || !featureList.length) return
    const bounds = new window.google.maps.LatLngBounds()
    const extend = (coords) => {
      if (!coords) return
      if (typeof coords[0] === 'number') {
        bounds.extend({ lat: coords[1], lng: coords[0] })
      } else {
        coords.forEach(extend)
      }
    }
    featureList.forEach(f => f.geometry && extend(f.geometry.coordinates))
    if (!bounds.isEmpty()) mapRef.current.fitBounds(bounds, 60)
  }, [])

  const processKML = useCallback((text, name) => {
    setError('')
    try {
      const parser = new DOMParser()
      const doc = parser.parseFromString(text, 'text/xml')
      const parseErr = doc.querySelector('parsererror')
      if (parseErr) throw new Error('Geçersiz XML formatı')
      const geojson = kml(doc)
      if (!geojson.features || geojson.features.length === 0) {
        setError('KML dosyasında görüntülenebilir öğe bulunamadı.')
        return
      }
      setFeatures(geojson.features)
      setFileName(name)
      setSelected(null)
      setTimeout(() => fitBoundsToFeatures(geojson.features), 100)
    } catch (e) {
      setError('KML dosyası okunamadı: ' + e.message)
    }
  }, [fitBoundsToFeatures])

  const handleFile = useCallback((file) => {
    if (!file) return
    if (!file.name.match(/\.kml$/i)) {
      setError('Lütfen .kml uzantılı bir dosya seçin.')
      return
    }
    const reader = new FileReader()
    reader.onload = (e) => processKML(e.target.result, file.name)
    reader.onerror = () => setError('Dosya okunamadı.')
    reader.readAsText(file)
  }, [processKML])

  const onFileInput = (e) => { handleFile(e.target.files[0]); e.target.value = '' }
  const onDrop = useCallback((e) => { e.preventDefault(); setIsDragging(false); handleFile(e.dataTransfer.files[0]) }, [handleFile])
  const onDragOver = (e) => { e.preventDefault(); setIsDragging(true) }
  const onDragLeave = () => setIsDragging(false)
  const clearKML = () => { setFeatures([]); setFileName(''); setSelected(null); setError('') }

  if (loadError) {
    return (
      <div className="error-screen">
        <div className="error-screen-icon">🗺️</div>
        <h2>Google Maps yüklenemedi</h2>
        <p>
          <code>VITE_GOOGLE_MAPS_API_KEY</code> ortam değişkenini kontrol edin.
        </p>
        <p className="error-detail">{loadError.message}</p>
      </div>
    )
  }

  if (!isLoaded) {
    return (
      <div className="loading-screen">
        <div className="spinner" />
        <p>Harita yükleniyor...</p>
      </div>
    )
  }

  return (
    <div className="app">
      <header className="header">
        <div className="header-left">
          <span className="logo-icon">🌍</span>
          <h1 className="app-title">KML Görüntüleyici</h1>
        </div>
        <div className="header-right">
          {fileName && (
            <div className="file-badge">
              <span className="file-icon">📄</span>
              <span className="file-name">{fileName}</span>
              <span className="feature-count">{features.length} öğe</span>
              <button className="clear-btn" onClick={clearKML} title="Temizle">✕</button>
            </div>
          )}
          <label className={`upload-btn${isDragging ? ' dragging' : ''}`} onDrop={onDrop} onDragOver={onDragOver} onDragLeave={onDragLeave}>
            <input type="file" accept=".kml" onChange={onFileInput} style={{ display: 'none' }} />
            📂 KML Yükle
          </label>
        </div>
      </header>

      {error && (
        <div className="error-bar">
          <span>⚠️ {error}</span>
          <button className="error-close" onClick={() => setError('')}>✕</button>
        </div>
      )}

      <div className="map-wrapper">
        {features.length === 0 && !error && (
          <div
            className={`drop-overlay${isDragging ? ' dragging' : ''}`}
            onDrop={onDrop}
            onDragOver={onDragOver}
            onDragLeave={onDragLeave}
          >
            <div className="drop-content">
              <div className="drop-icon">📂</div>
              <p className="drop-title">KML dosyasını buraya sürükleyin</p>
              <p className="drop-or">veya</p>
              <label className="upload-btn-large">
                <input type="file" accept=".kml" onChange={onFileInput} style={{ display: 'none' }} />
                Dosya Seç
              </label>
            </div>
          </div>
        )}

        <GoogleMap
          mapContainerClassName="map"
          center={DEFAULT_CENTER}
          zoom={DEFAULT_ZOOM}
          options={MAP_OPTIONS}
          onLoad={onMapLoad}
        >
          {features.map((feature, i) => (
            <Feature key={i} feature={feature} onClick={setSelected} />
          ))}

          {selected && (() => {
            const pos = getFeatureCenter(selected)
            if (!pos) return null
            const props = selected.properties || {}
            return (
              <InfoWindow position={pos} onCloseClick={() => setSelected(null)}>
                <div className="info-window">
                  {props.name && <h3>{props.name}</h3>}
                  {props.description && (
                    <div className="info-desc" dangerouslySetInnerHTML={{ __html: props.description }} />
                  )}
                  {!props.name && !props.description && <p className="info-empty">Özellik bilgisi yok</p>}
                </div>
              </InfoWindow>
            )
          })()}
        </GoogleMap>
      </div>
    </div>
  )
}
