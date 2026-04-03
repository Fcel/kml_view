"""KML dosyası parser — Point, LineString, Polygon desteği."""
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import Optional


NS = {
    'kml': 'http://www.opengis.net/kml/2.2',
    'kml22': 'http://earth.google.com/kml/2.2',
    'kml21': 'http://earth.google.com/kml/2.1',
}


@dataclass
class KmlStyle:
    stroke_color: str = '#FF4444'
    stroke_width: float = 2.0
    fill_color: str = '#FF4444'
    fill_opacity: float = 0.35


@dataclass
class KmlFeature:
    name: str = ''
    description: str = ''
    geometry_type: str = ''          # 'Point' | 'LineString' | 'Polygon'
    coordinates: list = field(default_factory=list)   # [(lon,lat), ...]
    rings: list = field(default_factory=list)         # Polygon için [[(lon,lat),...],...]
    style: KmlStyle = field(default_factory=KmlStyle)


def _kml_color_to_hex(kml_color: str) -> tuple[str, float]:
    """KML aabbggrr → (#rrggbb, opacity)"""
    c = kml_color.strip().lstrip('#')
    if len(c) == 8:
        a = int(c[0:2], 16) / 255.0
        r = c[6:8]; g = c[4:6]; b = c[2:4]
        return f'#{r}{g}{b}', a
    return '#FF4444', 0.35


def _find_text(el, tags: list[str]) -> Optional[str]:
    """Namespace'siz tag ara."""
    for child in el.iter():
        tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
        if tag in tags and child.text:
            return child.text.strip()
    return None


def _parse_coords(text: str) -> list[tuple[float, float]]:
    """KML koordinat string → [(lon, lat), ...]"""
    pts = []
    for token in text.strip().split():
        parts = token.split(',')
        if len(parts) >= 2:
            try:
                pts.append((float(parts[0]), float(parts[1])))
            except ValueError:
                pass
    return pts


def _parse_style(style_el) -> KmlStyle:
    style = KmlStyle()
    for child in style_el.iter():
        tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
        if tag == 'color' and child.text:
            parent_tag = ''
            # parent'ı bulmak için iter'ı kullan
        # Basit yaklaşım: color değerlerini sırayla al
    colors = []
    widths = []
    for child in style_el.iter():
        tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
        if tag == 'color' and child.text:
            colors.append((child.text.strip(), _get_parent_tag(style_el, child)))
        if tag == 'width' and child.text:
            try:
                widths.append(float(child.text.strip()))
            except ValueError:
                pass

    for color_str, parent in colors:
        if parent == 'LineStyle':
            hex_c, _ = _kml_color_to_hex(color_str)
            style.stroke_color = hex_c
        elif parent == 'PolyStyle':
            hex_c, op = _kml_color_to_hex(color_str)
            style.fill_color = hex_c
            style.fill_opacity = op

    if widths:
        style.stroke_width = widths[0]
    return style


def _get_parent_tag(root, target) -> str:
    """Bir elementin parent tag'ini bul."""
    for parent in root.iter():
        for child in list(parent):
            if child is target:
                return parent.tag.split('}')[-1] if '}' in parent.tag else parent.tag
    return ''


def parse_kml(content: str) -> list[KmlFeature]:
    """KML string → KmlFeature listesi"""
    # BOM ve boşluk temizle
    content = content.strip().lstrip('\ufeff')
    try:
        root = ET.fromstring(content)
    except ET.ParseError as e:
        raise ValueError(f'Geçersiz KML: {e}')

    # Stilleri topla
    styles: dict[str, KmlStyle] = {}
    for el in root.iter():
        tag = el.tag.split('}')[-1] if '}' in el.tag else el.tag
        if tag == 'Style':
            sid = el.get('id')
            if sid:
                styles[sid] = _parse_style(el)

    features: list[KmlFeature] = []

    for el in root.iter():
        tag = el.tag.split('}')[-1] if '}' in el.tag else el.tag
        if tag != 'Placemark':
            continue

        name = _find_text(el, ['name']) or ''
        desc = _find_text(el, ['description']) or ''

        # Style referansı
        style = KmlStyle()
        style_url = _find_text(el, ['styleUrl'])
        if style_url:
            key = style_url.lstrip('#')
            style = styles.get(key, KmlStyle())

        # Inline style
        for child in el:
            ctag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
            if ctag == 'Style':
                style = _parse_style(child)

        # Geometri
        for geom_el in el.iter():
            gtag = geom_el.tag.split('}')[-1] if '}' in geom_el.tag else geom_el.tag

            if gtag == 'Point':
                coord_text = _find_text(geom_el, ['coordinates'])
                if coord_text:
                    pts = _parse_coords(coord_text)
                    if pts:
                        features.append(KmlFeature(
                            name=name, description=desc,
                            geometry_type='Point',
                            coordinates=pts, style=style
                        ))

            elif gtag == 'LineString':
                coord_text = _find_text(geom_el, ['coordinates'])
                if coord_text:
                    pts = _parse_coords(coord_text)
                    if pts:
                        features.append(KmlFeature(
                            name=name, description=desc,
                            geometry_type='LineString',
                            coordinates=pts, style=style
                        ))

            elif gtag == 'Polygon':
                rings = []
                for boundary in geom_el.iter():
                    btag = boundary.tag.split('}')[-1] if '}' in boundary.tag else boundary.tag
                    if btag in ('outerBoundaryIs', 'innerBoundaryIs'):
                        coord_text = _find_text(boundary, ['coordinates'])
                        if coord_text:
                            pts = _parse_coords(coord_text)
                            if pts:
                                rings.append(pts)
                if rings:
                    features.append(KmlFeature(
                        name=name, description=desc,
                        geometry_type='Polygon',
                        rings=rings, style=style
                    ))

    return features
