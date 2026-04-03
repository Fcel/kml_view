import 'dart:math';

/// TUREF (Türkiye Ulusal Referans Çerçevesi) koordinat dönüşümleri
/// Elipsoit: GRS80  (TUREF, ETRS89 ile uyumlu)
/// Projeksiyon: Transverse Mercator (3° dilimler)
/// k0 = 1.0, False Easting = 500 000 m, False Northing = 0 m
class TurefConverter {
  // GRS80 elipsoiti
  static const double _a = 6378137.0;
  static const double _f = 1 / 298.257222101;
  static const double _b = _a * (1 - _f);
  static const double _e2 = 2 * _f - _f * _f;
  static const double _e = 0.0818191910428276; // sqrt(_e2)
  static const double _k0 = 1.0;
  static const double _fe = 500000.0; // false easting
  static const double _fn = 0.0;      // false northing

  // Türkiye'nin TUREF TM dilimleri (merkez boylamları)
  static const List<int> dilimler = [27, 30, 33, 36, 39, 42, 45];

  /// Tıklanan noktanın hangi dilime girdiğini döndürür
  static int aktifDilim(double lon) {
    for (final cm in dilimler) {
      if (lon >= cm - 1.5 && lon < cm + 1.5) return cm;
    }
    // Sınır dışı — en yakın dilimi ver
    return dilimler.reduce((a, b) => (lon - a).abs() < (lon - b).abs() ? a : b);
  }

  /// WGS84 / TUREF coğrafi → TUREF TM(merkez) projeksiyon
  /// Döndürür: (Easting, Northing) metre
  static (double, double) toTM(double latDeg, double lonDeg, int centralMeridian) {
    final lat = latDeg * pi / 180;
    final lon = lonDeg * pi / 180;
    final lon0 = centralMeridian * pi / 180;

    final sinLat = sin(lat);
    final cosLat = cos(lat);
    final tanLat = tan(lat);

    final e2 = _e2;
    final N = _a / sqrt(1 - e2 * sinLat * sinLat);
    final T = tanLat * tanLat;
    final C = e2 / (1 - e2) * cosLat * cosLat;
    final A = cosLat * (lon - lon0);

    // Meridyen yayı M
    final M = _meridianArc(lat);

    final E = _fe + _k0 * N * (
        A +
        (1 - T + C) * pow(A, 3) / 6 +
        (5 - 18 * T + T * T + 72 * C - 58 * (e2 / (1 - e2))) * pow(A, 5) / 120
    );

    final N_ = _fn + _k0 * (
        M +
        N * tanLat * (
            A * A / 2 +
            (5 - T + 9 * C + 4 * C * C) * pow(A, 4) / 24 +
            (61 - 58 * T + T * T + 600 * C - 330 * (e2 / (1 - e2))) * pow(A, 6) / 720
        )
    );

    return (E, N_);
  }

  static double _meridianArc(double lat) {
    final e2 = _e2;
    final e4 = e2 * e2;
    final e6 = e4 * e2;
    return _a * (
        (1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * lat -
        (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * sin(2 * lat) +
        (15 * e4 / 256 + 45 * e6 / 1024) * sin(4 * lat) -
        (35 * e6 / 3072) * sin(6 * lat)
    );
  }

  /// Tüm dilimler için koordinat hesapla
  static List<TurefKoordinat> tumDilimler(double lat, double lon) {
    return dilimler.map((cm) {
      final (e, n) = toTM(lat, lon, cm);
      return TurefKoordinat(dilim: cm, easting: e, northing: n);
    }).toList();
  }

  /// Decimal dereceyi DMS formatına çevir
  static String toDMS(double deg, {bool isLat = true}) {
    final d = deg.abs().floor();
    final mFull = (deg.abs() - d) * 60;
    final m = mFull.floor();
    final s = (mFull - m) * 60;
    final dir = isLat ? (deg >= 0 ? 'K' : 'G') : (deg >= 0 ? 'D' : 'B');
    return '$d°$m\'${s.toStringAsFixed(3)}"$dir';
  }
}

class TurefKoordinat {
  final int dilim;
  final double easting;
  final double northing;

  const TurefKoordinat({
    required this.dilim,
    required this.easting,
    required this.northing,
  });
}
