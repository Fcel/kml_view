"""
TUREF ve ED50 koordinat dönüşümleri.

TUREF : GRS80 elipsoiti, Transverse Mercator 3° dilimler, k0=1.0
ED50  : International/Hayford elipsoiti, UTM 6° dilimler, k0=0.9996
        WGS84 → ED50 Molodensky (Türkiye): ΔX=+84m, ΔY=+97m, ΔZ=+117m
"""
import math
from dataclasses import dataclass


# ── GRS80 (TUREF / WGS84) ──────────────────────────────────────────────────
_GRS_A  = 6_378_137.0
_GRS_F  = 1 / 298.257_222_101
_GRS_E2 = 2 * _GRS_F - _GRS_F ** 2

# ── International / Hayford (ED50) ─────────────────────────────────────────
_INT_A  = 6_378_388.0
_INT_F  = 1 / 297.0
_INT_E2 = 2 * _INT_F - _INT_F ** 2

# ── WGS84 → ED50 Molodensky (Türkiye) ─────────────────────────────────────
_DX, _DY, _DZ = 84.0, 97.0, 117.0

# ── TUREF 3° merkez boylamları ─────────────────────────────────────────────
TUREF_DILIMLER = [27, 30, 33, 36, 39, 42, 45]


# ───────────────────────────────────────────────────────────────────────────
#  Yardımcı: meridyen yayı ve TM projeksiyonu
# ───────────────────────────────────────────────────────────────────────────

def _meridian_arc(lat_rad: float, a: float, e2: float) -> float:
    e4 = e2 ** 2; e6 = e4 * e2
    return a * (
        (1 - e2/4 - 3*e4/64 - 5*e6/256)  * lat_rad
        - (3*e2/8 + 3*e4/32 + 45*e6/1024) * math.sin(2*lat_rad)
        + (15*e4/256 + 45*e6/1024)         * math.sin(4*lat_rad)
        - (35*e6/3072)                      * math.sin(6*lat_rad)
    )


def _tm(lat_deg: float, lon_deg: float, cm: int,
        a: float, e2: float, k0: float,
        fe: float = 500_000.0, fn: float = 0.0) -> tuple[float, float]:
    """Transverse Mercator projeksiyon → (Easting, Northing)."""
    lat  = math.radians(lat_deg)
    lon  = math.radians(lon_deg)
    lon0 = math.radians(cm)

    sin_lat = math.sin(lat); cos_lat = math.cos(lat); tan_lat = math.tan(lat)
    ep2 = e2 / (1 - e2)
    N = a / math.sqrt(1 - e2 * sin_lat**2)
    T = tan_lat**2
    C = ep2 * cos_lat**2
    A = cos_lat * (lon - lon0)
    M = _meridian_arc(lat, a, e2)

    E = fe + k0 * N * (
        A
        + (1 - T + C) * A**3 / 6
        + (5 - 18*T + T**2 + 72*C - 58*ep2) * A**5 / 120
    )
    Nv = fn + k0 * (
        M + N * tan_lat * (
            A**2 / 2
            + (5 - T + 9*C + 4*C**2) * A**4 / 24
            + (61 - 58*T + T**2 + 600*C - 330*ep2) * A**6 / 720
        )
    )
    return E, Nv


# ───────────────────────────────────────────────────────────────────────────
#  TUREF
# ───────────────────────────────────────────────────────────────────────────

def turef_aktif_dilim(lon_deg: float) -> int:
    for cm in TUREF_DILIMLER:
        if cm - 1.5 <= lon_deg < cm + 1.5:
            return cm
    return min(TUREF_DILIMLER, key=lambda x: abs(lon_deg - x))


def to_turef_tm(lat: float, lon: float, cm: int | None = None) -> tuple[float, float, int]:
    """WGS84 → TUREF TM. Döndürür: (E, N, dilim_cm)"""
    if cm is None:
        cm = turef_aktif_dilim(lon)
    e, n = _tm(lat, lon, cm, _GRS_A, _GRS_E2, 1.0)
    return e, n, cm


# ───────────────────────────────────────────────────────────────────────────
#  ED50
# ───────────────────────────────────────────────────────────────────────────

def _wgs84_to_ed50(lat_deg: float, lon_deg: float) -> tuple[float, float]:
    """WGS84 → ED50 Molodensky datum dönüşümü (Türkiye parametreleri)."""
    lat = math.radians(lat_deg)
    lon = math.radians(lon_deg)

    sin_lat = math.sin(lat); cos_lat = math.cos(lat)
    sin_lon = math.sin(lon); cos_lon = math.cos(lon)

    a1, f1, e12 = _GRS_A, _GRS_F, _GRS_E2
    a2, f2      = _INT_A, _INT_F
    da = a2 - a1
    df = f2 - f1
    b1 = a1 * (1 - f1)

    W  = math.sqrt(1 - e12 * sin_lat**2)
    N1 = a1 / W
    M1 = a1 * (1 - e12) / W**3

    d_lat = (1 / M1) * (
        _DY * cos_lat * sin_lon
        - _DX * cos_lat * cos_lon
        - _DZ * sin_lat
        + (a1 * da + (b1 / a1) * b1 * df) / N1 * e12 * sin_lat * cos_lat
        + df * (N1 * (1 - f1) + M1 * f1) * sin_lat * cos_lat
    )
    d_lon = (_DY * cos_lon - _DX * sin_lon) / (N1 * cos_lat)

    return lat_deg + math.degrees(d_lat), lon_deg + math.degrees(d_lon)


def ed50_zone(lon_deg: float) -> int:
    return int((lon_deg + 180) / 6) + 1


def ed50_cm(zone: int) -> int:
    return (zone - 1) * 6 - 180 + 3


@dataclass
class Ed50Result:
    zone: int
    cm: int
    easting: float
    northing: float


def to_ed50_utm(lat: float, lon: float) -> Ed50Result:
    """WGS84 → ED50 UTM. Datum dönüşümü + UTM projeksiyon."""
    ed50_lat, ed50_lon = _wgs84_to_ed50(lat, lon)
    zone = ed50_zone(ed50_lon)
    cm   = ed50_cm(zone)
    e, n = _tm(ed50_lat, ed50_lon, cm, _INT_A, _INT_E2, 0.9996)
    return Ed50Result(zone=zone, cm=cm, easting=e, northing=n)


# ───────────────────────────────────────────────────────────────────────────
#  Yardımcı: DMS
# ───────────────────────────────────────────────────────────────────────────

def to_dms(deg: float, is_lat: bool = True) -> str:
    d = int(abs(deg))
    m_full = (abs(deg) - d) * 60
    m = int(m_full)
    s = (m_full - m) * 60
    if is_lat:
        direction = 'K' if deg >= 0 else 'G'
    else:
        direction = 'D' if deg >= 0 else 'B'
    return f"{d}°{m}'{s:.3f}\"{direction}"
