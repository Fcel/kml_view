import 'package:google_maps_flutter/google_maps_flutter.dart';

enum KmlGeometryType { point, lineString, polygon, unknown }

class KmlStyle {
  final String? strokeColor;
  final double strokeWidth;
  final String? fillColor;
  final double fillOpacity;

  const KmlStyle({
    this.strokeColor,
    this.strokeWidth = 2.0,
    this.fillColor,
    this.fillOpacity = 0.35,
  });
}

class KmlFeature {
  final String? name;
  final String? description;
  final KmlGeometryType type;
  final List<LatLng> points; // Point veya LineString için
  final List<List<LatLng>> rings; // Polygon için (outer + inner)
  final KmlStyle style;

  const KmlFeature({
    this.name,
    this.description,
    required this.type,
    this.points = const [],
    this.rings = const [],
    this.style = const KmlStyle(),
  });
}
