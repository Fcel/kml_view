import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:xml/xml.dart';
import '../models/kml_feature.dart';

class KmlParser {
  static List<KmlFeature> parse(String kmlContent) {
    final document = XmlDocument.parse(kmlContent);
    final features = <KmlFeature>[];
    final styles = _parseStyles(document);
    final placemarks = document.findAllElements('Placemark');
    for (final placemark in placemarks) {
      final feature = _parsePlacemark(placemark, styles);
      if (feature != null) features.add(feature);
    }
    return features;
  }

  static Map<String, KmlStyle> _parseStyles(XmlDocument doc) {
    final styles = <String, KmlStyle>{};
    for (final style in doc.findAllElements('Style')) {
      final id = style.getAttribute('id');
      if (id == null) continue;
      styles[id] = _parseStyle(style);
    }
    return styles;
  }

  static KmlStyle _parseStyle(XmlElement styleEl) {
    String? strokeColor;
    double strokeWidth = 2.0;
    String? fillColor;
    double fillOpacity = 0.35;

    final lineStyle = styleEl.findElements('LineStyle').firstOrNull;
    if (lineStyle != null) {
      final colorEl = lineStyle.findElements('color').firstOrNull;
      if (colorEl != null) strokeColor = _kmlColorToHex(colorEl.innerText.trim());
      final widthEl = lineStyle.findElements('width').firstOrNull;
      if (widthEl != null) strokeWidth = double.tryParse(widthEl.innerText.trim()) ?? 2.0;
    }

    final polyStyle = styleEl.findElements('PolyStyle').firstOrNull;
    if (polyStyle != null) {
      final colorEl = polyStyle.findElements('color').firstOrNull;
      if (colorEl != null) {
        final parsed = _kmlColorToHexWithOpacity(colorEl.innerText.trim());
        fillColor = parsed.$1;
        fillOpacity = parsed.$2;
      }
    }

    return KmlStyle(
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      fillColor: fillColor,
      fillOpacity: fillOpacity,
    );
  }

  static KmlFeature? _parsePlacemark(XmlElement placemark, Map<String, KmlStyle> styles) {
    final name = placemark.findElements('name').firstOrNull?.innerText.trim();
    final description = placemark.findElements('description').firstOrNull?.innerText.trim();

    // Style referansı
    KmlStyle style = const KmlStyle();
    final styleUrl = placemark.findElements('styleUrl').firstOrNull?.innerText.trim();
    if (styleUrl != null) {
      final key = styleUrl.startsWith('#') ? styleUrl.substring(1) : styleUrl;
      style = styles[key] ?? const KmlStyle();
    }
    final inlineStyle = placemark.findElements('Style').firstOrNull;
    if (inlineStyle != null) style = _parseStyle(inlineStyle);

    // Point
    final point = placemark.findAllElements('Point').firstOrNull;
    if (point != null) {
      final coords = _parseCoordsSingle(point);
      if (coords != null) {
        return KmlFeature(name: name, description: description, type: KmlGeometryType.point, points: [coords], style: style);
      }
    }

    // LineString
    final line = placemark.findAllElements('LineString').firstOrNull;
    if (line != null) {
      final coords = _parseCoordsMulti(line);
      if (coords.isNotEmpty) {
        return KmlFeature(name: name, description: description, type: KmlGeometryType.lineString, points: coords, style: style);
      }
    }

    // Polygon
    final polygon = placemark.findAllElements('Polygon').firstOrNull;
    if (polygon != null) {
      final rings = <List<LatLng>>[];
      final outer = polygon.findAllElements('outerBoundaryIs').firstOrNull;
      if (outer != null) {
        final coords = _parseCoordsMulti(outer);
        if (coords.isNotEmpty) rings.add(coords);
      }
      for (final inner in polygon.findAllElements('innerBoundaryIs')) {
        final coords = _parseCoordsMulti(inner);
        if (coords.isNotEmpty) rings.add(coords);
      }
      if (rings.isNotEmpty) {
        return KmlFeature(name: name, description: description, type: KmlGeometryType.polygon, rings: rings, style: style);
      }
    }

    // MultiGeometry — parse each child recursively
    final multi = placemark.findAllElements('MultiGeometry').firstOrNull;
    if (multi != null) {
      // Return first valid geometry for simplicity
      final subPlacemark = XmlElement(XmlName('Placemark'));
      // Just collect all children's features — return first non-null
      for (final child in multi.childElements) {
        final wrapper = _wrapGeometry(child, name, description, style);
        if (wrapper != null) return wrapper;
      }
    }

    return null;
  }

  static KmlFeature? _wrapGeometry(XmlElement geom, String? name, String? desc, KmlStyle style) {
    if (geom.name.local == 'Point') {
      final coords = _parseCoordsSingle(geom);
      if (coords != null) return KmlFeature(name: name, description: desc, type: KmlGeometryType.point, points: [coords], style: style);
    }
    if (geom.name.local == 'LineString') {
      final coords = _parseCoordsMulti(geom);
      if (coords.isNotEmpty) return KmlFeature(name: name, description: desc, type: KmlGeometryType.lineString, points: coords, style: style);
    }
    if (geom.name.local == 'Polygon') {
      final rings = <List<LatLng>>[];
      final outer = geom.findAllElements('outerBoundaryIs').firstOrNull;
      if (outer != null) {
        final coords = _parseCoordsMulti(outer);
        if (coords.isNotEmpty) rings.add(coords);
      }
      if (rings.isNotEmpty) return KmlFeature(name: name, description: desc, type: KmlGeometryType.polygon, rings: rings, style: style);
    }
    return null;
  }

  static LatLng? _parseCoordsSingle(XmlElement el) {
    final text = el.findAllElements('coordinates').firstOrNull?.innerText.trim();
    if (text == null || text.isEmpty) return null;
    final parts = text.split(RegExp(r'[\s,]+'));
    if (parts.length < 2) return null;
    final lng = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lng == null || lat == null) return null;
    return LatLng(lat, lng);
  }

  static List<LatLng> _parseCoordsMulti(XmlElement el) {
    final text = el.findAllElements('coordinates').firstOrNull?.innerText.trim();
    if (text == null || text.isEmpty) return [];
    final result = <LatLng>[];
    for (final tuple in text.trim().split(RegExp(r'\s+'))) {
      final parts = tuple.split(',');
      if (parts.length < 2) continue;
      final lng = double.tryParse(parts[0]);
      final lat = double.tryParse(parts[1]);
      if (lng != null && lat != null) result.add(LatLng(lat, lng));
    }
    return result;
  }

  // KML renk: aabbggrr → hex #rrggbb
  static String _kmlColorToHex(String kmlColor) {
    if (kmlColor.length != 8) return '#FF4444';
    final r = kmlColor.substring(6, 8);
    final g = kmlColor.substring(4, 6);
    final b = kmlColor.substring(2, 4);
    return '#$r$g$b';
  }

  static (String, double) _kmlColorToHexWithOpacity(String kmlColor) {
    if (kmlColor.length != 8) return ('#FF4444', 0.35);
    final a = int.parse(kmlColor.substring(0, 2), radix: 16) / 255.0;
    final r = kmlColor.substring(6, 8);
    final g = kmlColor.substring(4, 6);
    final b = kmlColor.substring(2, 4);
    return ('#$r$g$b', a);
  }
}
