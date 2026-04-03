"""
KeMaL — Web  (Streamlit + Folium)
Google Earth benzeri satellite altlık, KML görüntüleyici, TUREF/ED50 koordinat paneli.
"""
import folium
import streamlit as st
from streamlit_folium import st_folium
from streamlit_js_eval import get_geolocation
from branca.element import MacroElement
from jinja2 import Template

from kml_parser import parse_kml, KmlFeature
from turef_converter import to_turef_tm, to_ed50_utm, to_dms


# ── Layer tıklamalarını harita click eventine ilet ─────────────────────────
class LayerClickPropagator(MacroElement):
    _template = Template(u"""
        {% macro script(this, kwargs) %}
        (function() {
            var m = {{ this._parent.get_name() }};
            function attach(layer) {
                if (typeof layer.on === 'function') {
                    layer.on('click', function(e) {
                        m.fire('click', {latlng: e.latlng, originalEvent: e.originalEvent});
                    });
                }
            }
            m.eachLayer(attach);
            m.on('layeradd', function(e) { attach(e.layer); });
        })();
        {% endmacro %}
    """)
    def __init__(self):
        super().__init__()
        self._name = 'LayerClickPropagator'


# ─── Sayfa ─────────────────────────────────────────────────────────────────
st.set_page_config(page_title='KeMaL', page_icon='🌍', layout='wide',
                   initial_sidebar_state='expanded')

st.markdown("""
<style>
.stApp { background:#0a0a18; color:#e0e0e0; }
[data-testid="stSidebar"] { background:#0f0f1e !important; }
[data-testid="stSidebar"] * { color:#e0e0e0 !important; }
hr { border-color:rgba(255,255,255,0.06) !important; }

.coord-card {
    background:rgba(255,255,255,0.04); border-radius:12px;
    padding:14px 16px; margin-bottom:10px;
    border:1px solid rgba(255,255,255,0.08);
}
.coord-title {
    font-size:11px; font-weight:700; letter-spacing:.5px;
    margin-bottom:10px; padding-bottom:6px;
    border-bottom:1px solid rgba(255,255,255,0.06);
}
.coord-row { display:flex; justify-content:space-between; font-size:12px; margin-bottom:5px; }
.coord-label { color:#888; }
.coord-value { color:#fff; font-family:monospace; font-weight:600; }
.coord-dms   { color:#555; font-family:monospace; font-size:11px; }
.badge { display:inline-block; padding:2px 8px; border-radius:5px;
         font-size:10px; font-weight:700; margin-left:8px; }
.b-blue   { background:rgba(74,158,255,.15); color:#4a9eff; border:1px solid rgba(74,158,255,.3); }
.b-orange { background:rgba(255,159,10,.15);  color:#ff9f0a; border:1px solid rgba(255,159,10,.3); }
.b-green  { background:rgba(52,199,89,.15);   color:#34c759; border:1px solid rgba(52,199,89,.3); }

.hint-box {
    color:#444; font-size:13px; padding:20px 12px; text-align:center;
    border:1px dashed #222; border-radius:10px; line-height:1.7;
}
.feature-item {
    padding:6px 10px; border-radius:7px; margin-bottom:4px;
    background:rgba(255,255,255,0.04); font-size:12px;
}
</style>
""", unsafe_allow_html=True)

# ─── Session state ─────────────────────────────────────────────────────────
for k, v in [('features', []), ('file_name', None),
              ('my_location', None), ('gps_active', False),
              ('uploader_key', 0)]:
    if k not in st.session_state:
        st.session_state[k] = v


# ─── Yardımcılar ───────────────────────────────────────────────────────────
def _kml_bounds(features):
    lats, lons = [], []
    for f in features:
        pts = f.coordinates[:]
        for r in f.rings:
            pts += r
        for lon, lat in pts:
            lats.append(lat); lons.append(lon)
    if not lats:
        return None
    return [[min(lats), min(lons)], [max(lats), max(lons)]]


def build_map(features, my_location=None):
    m = folium.Map(location=[39.0, 35.0], zoom_start=6, tiles=None, prefer_canvas=True)

    folium.TileLayer(
        tiles='https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        attr='ESRI World Imagery', name='🛰 Satellite', overlay=False, control=True, max_zoom=20,
    ).add_to(m)
    folium.TileLayer(tiles='OpenStreetMap', name='🗺 OpenStreetMap',
                     overlay=False, control=True).add_to(m)

    for i, f in enumerate(features):
        name = f.name or f'Özellik {i+1}'
        popup_html = f'<b>{name}</b>' + (f'<br>{f.description}' if f.description else '')

        if f.geometry_type == 'Point' and f.coordinates:
            lon, lat = f.coordinates[0]
            folium.Marker([lat, lon], tooltip=name,
                          popup=folium.Popup(popup_html, max_width=280)).add_to(m)

        elif f.geometry_type == 'LineString' and f.coordinates:
            folium.PolyLine([[lat, lon] for lon, lat in f.coordinates],
                            color=f.style.stroke_color,
                            weight=max(1, f.style.stroke_width),
                            opacity=0.9, tooltip=name,
                            popup=folium.Popup(popup_html, max_width=280)).add_to(m)

        elif f.geometry_type == 'Polygon' and f.rings:
            folium.Polygon(
                locations=[[lat, lon] for lon, lat in f.rings[0]],
                holes=[[[lat, lon] for lon, lat in r] for r in f.rings[1:]] or None,
                color=f.style.stroke_color, weight=max(1, f.style.stroke_width),
                fill_color=f.style.fill_color, fill_opacity=f.style.fill_opacity,
                tooltip=name, popup=folium.Popup(popup_html, max_width=280),
            ).add_to(m)

    if features:
        b = _kml_bounds(features)
        if b:
            m.fit_bounds(b, padding=(50, 50), max_zoom=17)

    if my_location:
        ulat, ulon = my_location['lat'], my_location['lng']
        folium.CircleMarker([ulat, ulon], radius=10, color='#fff', weight=2,
                            fill=True, fill_color='#4a9eff', fill_opacity=1.0,
                            tooltip='Konumunuz', zIndexOffset=1000).add_to(m)
        folium.CircleMarker([ulat, ulon], radius=22, color='#4a9eff', weight=1.5,
                            fill=True, fill_color='#4a9eff', fill_opacity=0.15).add_to(m)
        if not features:
            m.fit_bounds([[ulat-.01, ulon-.01], [ulat+.01, ulon+.01]], max_zoom=16)

    folium.LayerControl(collapsed=False).add_to(m)
    LayerClickPropagator().add_to(m)
    return m


def coord_html(lat, lon):
    e_t, n_t, cm = to_turef_tm(lat, lon)
    ed = to_ed50_utm(lat, lon)
    return f"""
<div class="coord-card">
  <div class="coord-title" style="color:#4a9eff">
    TUREF / TM{cm} <span class="badge b-blue">3° dilim</span>
  </div>
  <div class="coord-row"><span class="coord-label">Doğu (E)</span>
    <span class="coord-value">{e_t:,.3f} m</span></div>
  <div class="coord-row"><span class="coord-label">Kuzey (N)</span>
    <span class="coord-value">{n_t:,.3f} m</span></div>
  <div class="coord-row"><span class="coord-label">Dilim</span>
    <span class="coord-value">TM{cm} — {cm}° cm</span></div>
</div>
<div class="coord-card">
  <div class="coord-title" style="color:#ff9f0a">
    ED50 / UTM Zon {ed.zone} <span class="badge b-orange">6° dilim</span>
  </div>
  <div class="coord-row"><span class="coord-label">Doğu (E)</span>
    <span class="coord-value">{ed.easting:,.3f} m</span></div>
  <div class="coord-row"><span class="coord-label">Kuzey (N)</span>
    <span class="coord-value">{ed.northing:,.3f} m</span></div>
  <div class="coord-row"><span class="coord-label">Zon</span>
    <span class="coord-value">Zon {ed.zone} — {ed.cm}° cm</span></div>
</div>
<div class="coord-card">
  <div class="coord-title" style="color:#34c759">
    Coğrafi <span class="badge b-green">WGS84</span>
  </div>
  <div class="coord-row"><span class="coord-label">Enlem</span>
    <span class="coord-value">{lat:.8f}°</span></div>
  <div class="coord-row" style="margin-top:-4px;margin-bottom:8px">
    <span></span><span class="coord-dms">{to_dms(lat, is_lat=True)}</span></div>
  <div class="coord-row"><span class="coord-label">Boylam</span>
    <span class="coord-value">{lon:.8f}°</span></div>
  <div class="coord-row" style="margin-top:-4px">
    <span></span><span class="coord-dms">{to_dms(lon, is_lat=False)}</span></div>
</div>"""


# ─── SIDEBAR — sadece KML yükleme + GPS ────────────────────────────────────
with st.sidebar:
    st.markdown("""
    <div style="display:flex;align-items:center;gap:10px;padding:8px 0 20px">
        <span style="font-size:32px">🌍</span>
        <div>
            <div style="font-size:24px;font-weight:800;letter-spacing:3px;color:#fff">KeMaL</div>
            <div style="font-size:11px;color:#555;letter-spacing:1px">Harita Görüntüleyici</div>
        </div>
    </div>
    """, unsafe_allow_html=True)

    # KML yükleme
    st.markdown('#### 📂 KML Dosyası')
    uploaded = st.file_uploader('KML yükle', type=['kml'], label_visibility='collapsed',
                                key=f'kml_up_{st.session_state.uploader_key}')
    if uploaded and uploaded.name != st.session_state.file_name:
        try:
            feats = parse_kml(uploaded.read().decode('utf-8', errors='replace'))
            if feats:
                st.session_state.features = feats
                st.session_state.file_name = uploaded.name
            else:
                st.warning('Görüntülenebilir öğe bulunamadı.')
        except Exception as e:
            st.error(f'KML okunamadı: {e}')

    if st.session_state.features:
        st.markdown(f"""
        <div style="background:rgba(74,158,255,.08);border:1px solid rgba(74,158,255,.2);
                    border-radius:8px;padding:8px 12px;margin:6px 0;font-size:12px">
            📄 <b>{st.session_state.file_name or ''}</b><br>
            <span style="color:#4a9eff;font-weight:700">{len(st.session_state.features)}</span>
            <span style="color:#666"> öğe</span>
        </div>""", unsafe_allow_html=True)

        # Öğe listesi
        icons = {'Point': '📌', 'LineString': '📏', 'Polygon': '🔷'}
        for f in st.session_state.features[:40]:
            st.markdown(
                f'<div class="feature-item">{icons.get(f.geometry_type,"•")} {f.name or f.geometry_type}</div>',
                unsafe_allow_html=True)
        if len(st.session_state.features) > 40:
            st.caption(f'+{len(st.session_state.features)-40} öğe daha…')

        if st.button('🗑 KML Temizle', use_container_width=True):
            st.session_state.features = []
            st.session_state.file_name = None
            st.session_state.uploader_key += 1
            st.rerun()

    st.markdown('---')

    # GPS
    st.markdown('#### 📡 Konum')
    if st.button('🔵 Konumu Güncelle' if st.session_state.my_location else '📡 Konumumu Göster',
                 use_container_width=True):
        st.session_state.gps_active = True

    if st.session_state.gps_active:
        with st.spinner('Konum alınıyor…'):
            loc = get_geolocation()
        st.session_state.gps_active = False
        if loc and loc.get('coords'):
            st.session_state.my_location = {
                'lat': loc['coords']['latitude'],
                'lng': loc['coords']['longitude'],
            }
        else:
            st.warning('Konum alınamadı.')

    if st.session_state.my_location:
        ml = st.session_state.my_location
        st.markdown(f"""
        <div style="background:rgba(74,158,255,.08);border:1px solid rgba(74,158,255,.2);
                    border-radius:8px;padding:8px 12px;margin:4px 0 8px;font-size:12px">
            🔵 <b style="color:#4a9eff">Aktif</b><br>
            <span style="color:#666;font-family:monospace">{ml['lat']:.6f}°, {ml['lng']:.6f}°</span>
        </div>""", unsafe_allow_html=True)
        if st.button('Konumu Temizle', use_container_width=True):
            st.session_state.my_location = None
            st.rerun()


# ─── ANA ALAN: harita (sol) + koordinatlar (sağ) ───────────────────────────
col_map, col_coord = st.columns([3, 1])

with col_map:
    m = build_map(st.session_state.features, my_location=st.session_state.my_location)
    map_data = st_folium(m, use_container_width=True, height=720,
                         returned_objects=['last_clicked'])

with col_coord:
    st.markdown('#### 📍 Koordinatlar')
    clicked = map_data.get('last_clicked') if map_data else None
    if clicked and isinstance(clicked, dict) and 'lat' in clicked:
        lat, lon = clicked['lat'], clicked['lng']
        st.markdown(coord_html(lat, lon), unsafe_allow_html=True)
        e_t, n_t, cm = to_turef_tm(lat, lon)
        ed = to_ed50_utm(lat, lon)
        st.text_area('', (
            f"TUREF TM{cm} (3° dilim)\n"
            f"Doğu  : {e_t:.3f} m\nKuzey : {n_t:.3f} m\n\n"
            f"ED50 UTM Zon {ed.zone} (6° dilim)\n"
            f"Doğu  : {ed.easting:.3f} m\nKuzey : {ed.northing:.3f} m\n\n"
            f"Coğrafi (WGS84)\n"
            f"Enlem  : {lat:.8f}°\nBoylam : {lon:.8f}°"
        ), height=220, label_visibility='collapsed')
    else:
        st.markdown("""
        <div class="hint-box">
            🖱️ Haritada herhangi<br>bir noktaya tıklayın<br><br>
            <span style="color:#333">TUREF · ED50 · WGS84</span>
        </div>""", unsafe_allow_html=True)
