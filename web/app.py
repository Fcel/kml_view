"""
KeMaL — Web  (Streamlit + Folium)
Google Earth benzeri satellite altlık, KML görüntüleyici, TUREF/ED50 koordinat paneli.
"""
import folium
import streamlit as st
from streamlit_folium import st_folium
from streamlit_js_eval import get_geolocation

from kml_parser import parse_kml, KmlFeature
from turef_converter import to_turef_tm, to_ed50_utm, to_dms

# ─── Sayfa ayarı ───────────────────────────────────────────────────────────
st.set_page_config(
    page_title='KeMaL',
    page_icon='🌍',
    layout='wide',
    initial_sidebar_state='expanded',
)

# ─── CSS ───────────────────────────────────────────────────────────────────
st.markdown("""
<style>
/* Genel arka plan */
.stApp { background: #0a0a18; color: #e0e0e0; }

/* Sidebar */
[data-testid="stSidebar"] { background: #0f0f1e !important; }
[data-testid="stSidebar"] * { color: #e0e0e0 !important; }

/* Başlık */
.kemal-header {
    display: flex; align-items: center; gap: 10px;
    padding: 8px 0 16px;
}
.kemal-title {
    font-size: 26px; font-weight: 800;
    letter-spacing: 3px; color: #fff;
}
.kemal-sub {
    font-size: 12px; color: #666; letter-spacing: 1px;
    margin-top: -4px;
}

/* Koordinat kartları */
.coord-card {
    background: rgba(255,255,255,0.04);
    border-radius: 12px; padding: 14px 16px;
    margin-bottom: 10px;
    border: 1px solid rgba(255,255,255,0.08);
}
.coord-card-title {
    font-size: 11px; font-weight: 700; letter-spacing: 0.5px;
    margin-bottom: 10px; padding-bottom: 6px;
    border-bottom: 1px solid rgba(255,255,255,0.06);
}
.coord-row {
    display: flex; justify-content: space-between;
    font-size: 12px; margin-bottom: 5px;
}
.coord-label { color: #888; }
.coord-value { color: #fff; font-family: monospace; font-weight: 600; }
.coord-dms   { color: #555; font-family: monospace; font-size: 11px; }

/* Badge */
.badge {
    display: inline-block; padding: 2px 8px;
    border-radius: 5px; font-size: 10px; font-weight: 700;
    margin-left: 8px; vertical-align: middle;
}
.badge-blue   { background: rgba(74,158,255,0.15); color: #4a9eff;
                border: 1px solid rgba(74,158,255,0.3); }
.badge-orange { background: rgba(255,159,10,0.15);  color: #ff9f0a;
                border: 1px solid rgba(255,159,10,0.3); }
.badge-green  { background: rgba(52,199,89,0.15);   color: #34c759;
                border: 1px solid rgba(52,199,89,0.3); }

/* Feature listesi */
.feature-item {
    padding: 6px 10px; border-radius: 7px; margin-bottom: 4px;
    background: rgba(255,255,255,0.04); font-size: 12px;
    cursor: pointer;
}
.feature-item:hover { background: rgba(74,158,255,0.1); }

/* Divider */
hr { border-color: rgba(255,255,255,0.06) !important; }
</style>
""", unsafe_allow_html=True)

# ─── Session state ──────────────────────────────────────────────────────────
if 'features' not in st.session_state:
    st.session_state.features = []
if 'file_name' not in st.session_state:
    st.session_state.file_name = None
if 'clicked' not in st.session_state:
    st.session_state.clicked = None        # {'lat': ..., 'lng': ...}
if 'my_location' not in st.session_state:
    st.session_state.my_location = None    # {'lat': ..., 'lng': ...}
if 'gps_active' not in st.session_state:
    st.session_state.gps_active = False


# ─── Yardımcılar ────────────────────────────────────────────────────────────

def hex_to_rgb(hex_color: str, opacity: float = 1.0) -> str:
    """#rrggbb → 'rgba(r,g,b,a)'"""
    h = hex_color.lstrip('#')
    if len(h) == 6:
        r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
        return f'rgba({r},{g},{b},{opacity})'
    return f'rgba(255,68,68,{opacity})'


def _kml_bounds(features: list[KmlFeature]):
    """Tüm feature'lardan bounding box hesapla → [[min_lat,min_lon],[max_lat,max_lon]]"""
    all_lats, all_lons = [], []
    for f in features:
        pts = f.coordinates[:]
        for ring in f.rings:
            pts += ring
        for lon, lat in pts:
            all_lats.append(lat); all_lons.append(lon)
    if not all_lats:
        return None
    return [[min(all_lats), min(all_lons)], [max(all_lats), max(all_lons)]]


def build_map(features: list[KmlFeature], my_location: dict | None = None) -> folium.Map:
    """Folium haritası oluştur — ESRI satellite altlık."""
    m = folium.Map(
        location=[39.0, 35.0],
        zoom_start=6,
        tiles=None,
        prefer_canvas=True,
    )

    # ── Satellite katman (ESRI World Imagery — ücretsiz) ──
    folium.TileLayer(
        tiles='https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        attr='ESRI World Imagery',
        name='🛰 Satellite (ESRI)',
        overlay=False,
        control=True,
        max_zoom=20,
    ).add_to(m)

    # ── OpenStreetMap (alternatif) ──
    folium.TileLayer(
        tiles='OpenStreetMap',
        name='🗺 OpenStreetMap',
        overlay=False,
        control=True,
    ).add_to(m)

    # ── KML geometrileri ──
    for i, f in enumerate(features):
        popup_html = _feature_popup(f)

        if f.geometry_type == 'Point' and f.coordinates:
            lon, lat = f.coordinates[0]
            folium.Marker(
                location=[lat, lon],
                tooltip=f.name or f'Özellik {i+1}',
                popup=folium.Popup(popup_html, max_width=280),
            ).add_to(m)

        elif f.geometry_type == 'LineString' and f.coordinates:
            folium.PolyLine(
                locations=[[lat, lon] for lon, lat in f.coordinates],
                color=f.style.stroke_color,
                weight=max(1, f.style.stroke_width),
                opacity=0.9,
                tooltip=f.name or f'Çizgi {i+1}',
                popup=folium.Popup(popup_html, max_width=280),
            ).add_to(m)

        elif f.geometry_type == 'Polygon' and f.rings:
            locations = [[lat, lon] for lon, lat in f.rings[0]]
            holes = [[[lat, lon] for lon, lat in ring] for ring in f.rings[1:]]
            folium.Polygon(
                locations=locations,
                holes=holes if holes else None,
                color=f.style.stroke_color,
                weight=max(1, f.style.stroke_width),
                fill_color=f.style.fill_color,
                fill_opacity=f.style.fill_opacity,
                tooltip=f.name or f'Poligon {i+1}',
                popup=folium.Popup(popup_html, max_width=280),
                # consumeTapEvents=False → tıklama harita click eventine ulaşır
            ).add_to(m)

    # ── KML alanına zoom (max 17 — altlık kaybolmasın) ──
    if features:
        bounds = _kml_bounds(features)
        if bounds:
            m.fit_bounds(bounds, padding=(50, 50), max_zoom=17)

    # ── Kullanıcı konumu ──
    if my_location:
        ulat = my_location['lat']
        ulon = my_location['lng']
        # Mavi dolu daire + doğruluk halkası
        folium.CircleMarker(
            location=[ulat, ulon],
            radius=10,
            color='#ffffff',
            weight=2,
            fill=True,
            fill_color='#4a9eff',
            fill_opacity=1.0,
            tooltip='Konumunuz',
            popup=folium.Popup(
                f'<b>Konumunuz</b><br>{ulat:.6f}°, {ulon:.6f}°',
                max_width=200,
            ),
            zIndexOffset=1000,
        ).add_to(m)
        folium.CircleMarker(
            location=[ulat, ulon],
            radius=22,
            color='#4a9eff',
            weight=1.5,
            fill=True,
            fill_color='#4a9eff',
            fill_opacity=0.15,
        ).add_to(m)

    folium.LayerControl(collapsed=False).add_to(m)

    return m


def _feature_popup(f: KmlFeature) -> str:
    name = f.name or 'Özellik'
    desc = f.description or ''
    return f"""
    <div style="font-family:system-ui;max-width:260px">
        <b style="font-size:14px">{name}</b>
        {'<hr style="margin:6px 0">' + desc if desc else ''}
    </div>
    """


def _coord_card_html(lat: float, lon: float) -> str:
    e_turef, n_turef, turef_cm = to_turef_tm(lat, lon)
    ed50 = to_ed50_utm(lat, lon)
    lat_dms = to_dms(lat, is_lat=True)
    lon_dms = to_dms(lon, is_lat=False)

    return f"""
<div class="coord-card">
  <div class="coord-card-title" style="color:#4a9eff">
    TUREF / TM{turef_cm}
    <span class="badge badge-blue">3° dilim</span>
  </div>
  <div class="coord-row">
    <span class="coord-label">Doğu (E)</span>
    <span class="coord-value">{e_turef:,.3f} m</span>
  </div>
  <div class="coord-row">
    <span class="coord-label">Kuzey (N)</span>
    <span class="coord-value">{n_turef:,.3f} m</span>
  </div>
  <div class="coord-row">
    <span class="coord-label">Dilim</span>
    <span class="coord-value">TM{turef_cm} — cm: {turef_cm}° D</span>
  </div>
</div>

<div class="coord-card">
  <div class="coord-card-title" style="color:#ff9f0a">
    ED50 / UTM Zon {ed50.zone}
    <span class="badge badge-orange">6° dilim</span>
  </div>
  <div class="coord-row">
    <span class="coord-label">Doğu (E)</span>
    <span class="coord-value">{ed50.easting:,.3f} m</span>
  </div>
  <div class="coord-row">
    <span class="coord-label">Kuzey (N)</span>
    <span class="coord-value">{ed50.northing:,.3f} m</span>
  </div>
  <div class="coord-row">
    <span class="coord-label">Zon</span>
    <span class="coord-value">Zon {ed50.zone} — cm: {ed50.cm}° D</span>
  </div>
</div>

<div class="coord-card">
  <div class="coord-card-title" style="color:#34c759">
    Coğrafi
    <span class="badge badge-green">WGS84</span>
  </div>
  <div class="coord-row">
    <span class="coord-label">Enlem</span>
    <span class="coord-value">{lat:.8f}°</span>
  </div>
  <div class="coord-row" style="margin-top:-4px;margin-bottom:8px">
    <span></span><span class="coord-dms">{lat_dms}</span>
  </div>
  <div class="coord-row">
    <span class="coord-label">Boylam</span>
    <span class="coord-value">{lon:.8f}°</span>
  </div>
  <div class="coord-row" style="margin-top:-4px">
    <span></span><span class="coord-dms">{lon_dms}</span>
  </div>
</div>
"""


# ─── Sidebar ────────────────────────────────────────────────────────────────
with st.sidebar:
    st.markdown("""
    <div class="kemal-header">
        <span style="font-size:32px">🌍</span>
        <div>
            <div class="kemal-title">KeMaL</div>
            <div class="kemal-sub">Harita Görüntüleyici</div>
        </div>
    </div>
    """, unsafe_allow_html=True)

    # ── GPS Konumu ──────────────────────────────────────────
    st.markdown('#### 📡 Konumum')

    gps_label = '🔵 Konumu Güncelle' if st.session_state.my_location else '📡 Konumumu Göster'
    if st.button(gps_label, use_container_width=True):
        st.session_state.gps_active = True

    if st.session_state.gps_active:
        with st.spinner('Konum alınıyor…'):
            loc = get_geolocation()
        st.session_state.gps_active = False
        if loc and loc.get('coords'):
            coords = loc['coords']
            st.session_state.my_location = {
                'lat': coords['latitude'],
                'lng': coords['longitude'],
            }
            st.rerun()
        else:
            st.warning('Konum alınamadı. Tarayıcı iznini kontrol edin.')

    if st.session_state.my_location:
        mlat = st.session_state.my_location['lat']
        mlng = st.session_state.my_location['lng']
        st.markdown(f"""
        <div style="background:rgba(74,158,255,0.08);border:1px solid rgba(74,158,255,0.2);
                    border-radius:8px;padding:8px 12px;margin:4px 0 8px;font-size:12px">
            🔵 <b style="color:#4a9eff">Konum aktif</b><br>
            <span style="color:#666;font-family:monospace">{mlat:.6f}°, {mlng:.6f}°</span>
        </div>
        """, unsafe_allow_html=True)
        if st.button('Konumu Temizle', use_container_width=True):
            st.session_state.my_location = None
            st.rerun()

    st.markdown('---')
    st.markdown('#### KML Dosyası')
    uploaded = st.file_uploader(
        'KML yükle',
        type=['kml'],
        label_visibility='collapsed',
    )

    if uploaded:
        try:
            content = uploaded.read().decode('utf-8', errors='replace')
            features = parse_kml(content)
            if features:
                st.session_state.features = features
                st.session_state.file_name = uploaded.name
                st.session_state.clicked = None
            else:
                st.warning('KML dosyasında görüntülenebilir öğe bulunamadı.')
        except Exception as e:
            st.error(f'KML okunamadı: {e}')

    if st.session_state.features:
        fname = st.session_state.file_name or ''
        count = len(st.session_state.features)
        st.markdown(f"""
        <div style="background:rgba(74,158,255,0.08);border:1px solid rgba(74,158,255,0.2);
                    border-radius:8px;padding:8px 12px;margin:8px 0;font-size:12px">
            📄 <b>{fname}</b><br>
            <span style="color:#4a9eff;font-weight:700">{count}</span>
            <span style="color:#666"> öğe yüklendi</span>
        </div>
        """, unsafe_allow_html=True)

        if st.button('🗑 Temizle', use_container_width=True):
            st.session_state.features = []
            st.session_state.file_name = None
            st.session_state.clicked = None
            st.rerun()

    st.markdown('---')

    # Koordinat paneli
    st.markdown('#### 📍 Koordinatlar')
    if st.session_state.clicked:
        lat = st.session_state.clicked['lat']
        lon = st.session_state.clicked['lng']
        st.markdown(f"""
        <div style="font-size:11px;color:#555;margin-bottom:10px">
            Tıklanan nokta
        </div>
        """, unsafe_allow_html=True)
        st.markdown(_coord_card_html(lat, lon), unsafe_allow_html=True)

        # Kopyalama alanı
        e_t, n_t, cm_t = to_turef_tm(lat, lon)
        ed50 = to_ed50_utm(lat, lon)
        copy_text = (
            f"TUREF TM{cm_t} (3° dilim)\n"
            f"Doğu  : {e_t:.3f} m\n"
            f"Kuzey : {n_t:.3f} m\n\n"
            f"ED50 UTM Zon {ed50.zone} (6° dilim)\n"
            f"Doğu  : {ed50.easting:.3f} m\n"
            f"Kuzey : {ed50.northing:.3f} m\n\n"
            f"Coğrafi (WGS84)\n"
            f"Enlem  : {lat:.8f}°\n"
            f"Boylam : {lon:.8f}°"
        )
        st.text_area('Kopyala', copy_text, height=180, label_visibility='collapsed')
    else:
        st.markdown("""
        <div style="color:#444;font-size:12px;padding:12px;text-align:center;
                    border:1px dashed #222;border-radius:8px">
            Haritada bir noktaya<br>tıklayın
        </div>
        """, unsafe_allow_html=True)

    # Öğe listesi
    if st.session_state.features:
        st.markdown('---')
        st.markdown('#### Öğeler')
        type_icons = {'Point': '📌', 'LineString': '📏', 'Polygon': '🔷'}
        for f in st.session_state.features[:50]:
            icon = type_icons.get(f.geometry_type, '•')
            label = f.name or f.geometry_type
            st.markdown(
                f'<div class="feature-item">{icon} {label}</div>',
                unsafe_allow_html=True
            )
        if len(st.session_state.features) > 50:
            st.caption(f'+{len(st.session_state.features)-50} öğe daha…')


# ─── Ana alan — Harita ──────────────────────────────────────────────────────
m = build_map(st.session_state.features, my_location=st.session_state.my_location)

# KML yoksa GPS konumuna zoom yap
if st.session_state.my_location and not st.session_state.features:
    mlat = st.session_state.my_location['lat']
    mlng = st.session_state.my_location['lng']
    m.fit_bounds(
        [[mlat - 0.01, mlng - 0.01], [mlat + 0.01, mlng + 0.01]],
        max_zoom=16,
    )

map_data = st_folium(
    m,
    use_container_width=True,
    height=700,
    returned_objects=['last_clicked', 'last_object_clicked_tooltip'],
)

# Tıklama koordinatını al — haritanın boş alanına tıklama
if map_data:
    clicked = map_data.get('last_clicked')
    if clicked and isinstance(clicked, dict) and 'lat' in clicked and 'lng' in clicked:
        if st.session_state.clicked != clicked:
            st.session_state.clicked = clicked
            st.rerun()
