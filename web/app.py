"""
KeMaL — Web  (Streamlit + Folium)
Google Earth benzeri satellite altlık, KML görüntüleyici, TUREF/ED50 koordinat paneli.
"""
import io
import folium
import streamlit as st
from streamlit_folium import st_folium

from kml_parser import parse_kml, KmlFeature
from turef_converter import to_turef_tm, to_ed50_utm, to_dms, turef_aktif_dilim

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
    st.session_state.clicked = None   # {'lat': ..., 'lng': ...}


# ─── Yardımcılar ────────────────────────────────────────────────────────────

def hex_to_rgb(hex_color: str, opacity: float = 1.0) -> str:
    """#rrggbb → 'rgba(r,g,b,a)'"""
    h = hex_color.lstrip('#')
    if len(h) == 6:
        r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
        return f'rgba({r},{g},{b},{opacity})'
    return f'rgba(255,68,68,{opacity})'


def build_map(features: list[KmlFeature]) -> folium.Map:
    """Folium haritası oluştur — ESRI satellite altlık."""
    # Merkez hesapla
    if features:
        all_lats, all_lons = [], []
        for f in features:
            pts = f.coordinates or (f.rings[0] if f.rings else [])
            for lon, lat in pts:
                all_lats.append(lat); all_lons.append(lon)
        center = [sum(all_lats)/len(all_lats), sum(all_lons)/len(all_lons)]
    else:
        center = [39.0, 35.0]

    m = folium.Map(
        location=center,
        zoom_start=7 if features else 6,
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
m = build_map(st.session_state.features)

map_data = st_folium(
    m,
    use_container_width=True,
    height=700,
    returned_objects=['last_clicked'],
)

# Tıklama koordinatını al
if map_data and map_data.get('last_clicked'):
    clicked = map_data['last_clicked']
    if clicked and {'lat', 'lng'} <= clicked.keys():
        if st.session_state.clicked != clicked:
            st.session_state.clicked = clicked
            st.rerun()
