import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/turef_converter.dart';

class KoordinatPanel extends StatelessWidget {
  final LatLng nokta;
  final VoidCallback onKapat;

  const KoordinatPanel({
    super.key,
    required this.nokta,
    required this.onKapat,
  });

  @override
  Widget build(BuildContext context) {
    final lat = nokta.latitude;
    final lon = nokta.longitude;

    // TUREF
    final turefDilim = TurefConverter.turefAktifDilim(lon);
    final (turefE, turefN) = TurefConverter.toTurefTM(lat, lon, turefDilim);

    // ED50
    final ed50 = TurefConverter.toEd50UTM(lat, lon);

    // Coğrafi
    final latDms = TurefConverter.toDMS(lat, isLat: true);
    final lonDms = TurefConverter.toDMS(lon, isLat: false);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Başlık satırı
            Row(
              children: [
                const Text('📍', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Nokta Koordinatları',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                GestureDetector(
                  onTap: onKapat,
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.close, color: Colors.white38, size: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── TUREF TM (3°) ──────────────────────────────
            _SectionCard(
              label: 'TUREF / TM$turefDilim',
              badge: '3° dilim',
              color: const Color(0xFF4A9EFF),
              children: [
                _KoordRow(label: 'Doğu (E)',  value: '${_fmt(turefE)} m', copyValue: _fmt(turefE)),
                _KoordRow(label: 'Kuzey (N)', value: '${_fmt(turefN)} m', copyValue: _fmt(turefN)),
                _KoordRow(label: 'Dilim',     value: 'TM$turefDilim  —  cm: $turefDilim° D', copyValue: 'TM$turefDilim'),
              ],
            ),
            const SizedBox(height: 10),

            // ── ED50 UTM (6°) ──────────────────────────────
            _SectionCard(
              label: 'ED50 / UTM Zon ${ed50.zone}',
              badge: '6° dilim',
              color: const Color(0xFFFF9F0A),
              children: [
                _KoordRow(label: 'Doğu (E)',  value: '${_fmt(ed50.easting)} m',  copyValue: _fmt(ed50.easting)),
                _KoordRow(label: 'Kuzey (N)', value: '${_fmt(ed50.northing)} m', copyValue: _fmt(ed50.northing)),
                _KoordRow(label: 'Zon',       value: 'Zon ${ed50.zone}  —  cm: ${ed50.centralMeridian}° D', copyValue: 'Zon ${ed50.zone}'),
              ],
            ),
            const SizedBox(height: 10),

            // ── Coğrafi (WGS84) ────────────────────────────
            _SectionCard(
              label: 'Coğrafi  (TUREF / WGS84)',
              color: const Color(0xFF34C759),
              children: [
                _KoordRow(
                  label: 'Enlem',
                  value: '${lat.toStringAsFixed(8)}°',
                  subValue: latDms,
                  copyValue: lat.toStringAsFixed(8),
                ),
                _KoordRow(
                  label: 'Boylam',
                  value: '${lon.toStringAsFixed(8)}°',
                  subValue: lonDms,
                  copyValue: lon.toStringAsFixed(8),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tümünü kopyala
            GestureDetector(
              onTap: () => _copyAll(context, turefDilim, turefE, turefN, ed50, lat, lon),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.copy, color: Colors.white54, size: 15),
                    SizedBox(width: 6),
                    Text('Tümünü Kopyala', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(3);

  void _copyAll(BuildContext ctx, int turefDilim, double tE, double tN,
      Ed50Koordinat ed50, double lat, double lon) {
    final text = [
      'TUREF TM$turefDilim (3° dilim)',
      'Doğu  : ${_fmt(tE)} m',
      'Kuzey : ${_fmt(tN)} m',
      '',
      'ED50 UTM Zon ${ed50.zone} (6° dilim)',
      'Doğu  : ${_fmt(ed50.easting)} m',
      'Kuzey : ${_fmt(ed50.northing)} m',
      '',
      'Coğrafi (WGS84)',
      'Enlem  : ${lat.toStringAsFixed(8)}°',
      'Boylam : ${lon.toStringAsFixed(8)}°',
    ].join('\n');

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text('Tüm koordinatlar kopyalandı'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ─── Section Card ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String label;
  final String? badge;
  final Color color;
  final List<Widget> children;

  const _SectionCard({required this.label, this.badge, required this.color, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Container(width: 3, height: 13,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                if (badge != null) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(badge!, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

// ─── Koordinat Satırı ─────────────────────────────────────────────────────

class _KoordRow extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final String copyValue;

  const _KoordRow({required this.label, required this.value, this.subValue, required this.copyValue});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: copyValue));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label kopyalandı'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace')),
                  if (subValue != null)
                    Text(subValue!,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
                ],
              ),
            ),
            const Icon(Icons.copy, color: Colors.white12, size: 13),
          ],
        ),
      ),
    );
  }
}
