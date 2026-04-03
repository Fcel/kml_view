import 'dart:math';

/// ─── TUREF ────────────────────────────────────────────────────────────────
/// Elipsoit : GRS80  (a=6378137, 1/f=298.257222101)
/// Projeksiyon : Transverse Mercator, 3° dilimler
/// k0=1.0, FE=500 000 m, FN=0 m
///
/// ─── ED50 ─────────────────────────────────────────────────────────────────
/// Elipsoit : International/Hayford  (a=6378388, 1/f=297)
/// Projeksiyon : UTM, 6° dilimler
/// k0=0.9996, FE=500 000 m, FN=0 m
/// Datum dönüşümü : WGS84 → ED50 (3-parametreli Molodensky, Türkiye)
///   ΔX=+84 m, ΔY=+97 m, ΔZ=+117 m
class TurefConverter {
  // ── GRS80 (TUREF) ──────────────────────────────────────────
  static const double _grsA  = 6378137.0;
  static const double _grsF  = 1 / 298.257222101;
  static const double _grsE2 = 2 * _grsF - _grsF * _grsF;

  // ── International/Hayford (ED50) ───────────────────────────
  static const double _intA  = 6378388.0;
  static const double _intF  = 1 / 297.0;
  static const double _intE2 = 2 * _intF - _intF * _intF;

  // ── Molodensky: WGS84 → ED50 (Türkiye) ────────────────────
  static const double _dx = 84.0;
  static const double _dy = 97.0;
  static const double _dz = 117.0;

  // ── TUREF dilimleri (3°, merkez boylamları) ────────────────
  static const List<int> turefDilimler = [27, 30, 33, 36, 39, 42, 45];

  // ─────────────────────────────────────────────────────────
  //  TUREF
  // ─────────────────────────────────────────────────────────

  /// Boylamdan aktif TUREF dilimini bul
  static int turefAktifDilim(double lon) {
    for (final cm in turefDilimler) {
      if (lon >= cm - 1.5 && lon < cm + 1.5) return cm;
    }
    return turefDilimler.reduce((a, b) =>
        (lon - a).abs() < (lon - b).abs() ? a : b);
  }

  /// WGS84/TUREF coğrafi → TUREF TM projeksiyon
  /// Döndürür: (Easting, Northing) metre
  static (double, double) toTurefTM(
      double latDeg, double lonDeg, int centralMeridian) {
    return _tm(latDeg, lonDeg, centralMeridian, _grsA, _grsE2, 1.0, 500000, 0);
  }

  // ─────────────────────────────────────────────────────────
  //  ED50
  // ─────────────────────────────────────────────────────────

  /// Boylamdan ED50 UTM zon numarasını bul (6° dilimler)
  static int ed50ZonNo(double lon) => ((lon + 180) / 6).floor() + 1;

  /// UTM zon merkez boylamı
  static int ed50CentralMeridian(int zone) => (zone - 1) * 6 - 180 + 3;

  /// WGS84 coğrafi → ED50 UTM projeksiyon
  /// Adım 1: WGS84 → ED50 datum dönüşümü (Molodensky)
  /// Adım 2: ED50 lat/lon → UTM TM projeksiyon
  /// Döndürür: (Easting, Northing, zonNo, centralMeridian)
  static Ed50Koordinat toEd50UTM(double wgsLatDeg, double wgsLonDeg) {
    final (ed50Lat, ed50Lon) = _wgs84ToEd50(wgsLatDeg, wgsLonDeg);
    final zone = ed50ZonNo(ed50Lon);
    final cm   = ed50CentralMeridian(zone);
    final (e, n) = _tm(ed50Lat, ed50Lon, cm, _intA, _intE2, 0.9996, 500000, 0);
    return Ed50Koordinat(zone: zone, centralMeridian: cm, easting: e, northing: n);
  }

  /// WGS84 → ED50 Molodensky dönüşümü
  static (double, double) _wgs84ToEd50(double latDeg, double lonDeg) {
    final lat = latDeg * pi / 180;
    final lon = lonDeg * pi / 180;

    final sinLat = sin(lat);
    final cosLat = cos(lat);
    final sinLon = sin(lon);
    final cosLon = cos(lon);

    // WGS84 parametreleri
    final a1  = _grsA;
    final f1  = _grsF;
    final e12 = _grsE2;
    // ED50 parametreleri
    final a2  = _intA;
    final f2  = _intF;

    final da = a2 - a1;
    final df = f2 - f1;

    final W   = sqrt(1 - e12 * sinLat * sinLat);
    final N1  = a1 / W;
    final M1  = a1 * (1 - e12) / (W * W * W);
    final b1  = a1 * (1 - f1);

    final dLat = (1 / (M1)) * (
        _dy * cosLat * sinLon -
        _dx * cosLat * cosLon -
        _dz * sinLat +
        (a1 * da + (b1 / a1) * db(a1, f1) * df) / (N1) * e12 * sinLat * cosLat +
        df * (N1 * (1 - f1) + M1 * f1) * sinLat * cosLat
    );

    final dLon = (_dy * cosLon - _dx * sinLon) / (N1 * cosLat);

    final newLat = latDeg + dLat * 180 / pi;
    final newLon = lonDeg + dLon * 180 / pi;
    return (newLat, newLon);
  }

  static double db(double a, double f) => a * (1 - f);

  // ─────────────────────────────────────────────────────────
  //  Ortak TM projeksiyon
  // ─────────────────────────────────────────────────────────

  static (double, double) _tm(double latDeg, double lonDeg, int cm,
      double a, double e2, double k0, double fe, double fn) {
    final lat  = latDeg * pi / 180;
    final lon  = lonDeg * pi / 180;
    final lon0 = cm * pi / 180;

    final sinLat = sin(lat);
    final cosLat = cos(lat);
    final tanLat = tan(lat);

    final N = a / sqrt(1 - e2 * sinLat * sinLat);
    final T = tanLat * tanLat;
    final C = e2 / (1 - e2) * cosLat * cosLat;
    final A = cosLat * (lon - lon0);
    final ep2 = e2 / (1 - e2);

    final M = _meridianArc(lat, a, e2);

    final E = fe + k0 * N * (
        A +
        (1 - T + C) * pow(A, 3) / 6 +
        (5 - 18 * T + T * T + 72 * C - 58 * ep2) * pow(A, 5) / 120
    );

    final Nv = fn + k0 * (
        M +
        N * tanLat * (
            A * A / 2 +
            (5 - T + 9 * C + 4 * C * C) * pow(A, 4) / 24 +
            (61 - 58 * T + T * T + 600 * C - 330 * ep2) * pow(A, 6) / 720
        )
    );

    return (E, Nv);
  }

  static double _meridianArc(double lat, double a, double e2) {
    final e4 = e2 * e2;
    final e6 = e4 * e2;
    return a * (
        (1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * lat -
        (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * sin(2 * lat) +
        (15 * e4 / 256 + 45 * e6 / 1024) * sin(4 * lat) -
        (35 * e6 / 3072) * sin(6 * lat)
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Yardımcılar
  // ─────────────────────────────────────────────────────────

  /// Decimal → DMS string
  static String toDMS(double deg, {bool isLat = true}) {
    final d    = deg.abs().floor();
    final mFull = (deg.abs() - d) * 60;
    final m    = mFull.floor();
    final s    = (mFull - m) * 60;
    final dir  = isLat ? (deg >= 0 ? 'K' : 'G') : (deg >= 0 ? 'D' : 'B');
    return '$d°$m\'${s.toStringAsFixed(3)}"$dir';
  }
}

class TurefKoordinat {
  final int dilim;
  final double easting;
  final double northing;
  const TurefKoordinat({required this.dilim, required this.easting, required this.northing});
}

class Ed50Koordinat {
  final int zone;
  final int centralMeridian;
  final double easting;
  final double northing;
  const Ed50Koordinat({
    required this.zone,
    required this.centralMeridian,
    required this.easting,
    required this.northing,
  });
  String get zonAdi => 'Zon $zone (${centralMeridian}° cm)';
}
