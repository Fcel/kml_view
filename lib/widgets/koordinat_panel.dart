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
    final dilim = TurefConverter.aktifDilim(lon);
    final (easting, northing) = TurefConverter.toTM(lat, lon, dilim);

    final latDms = TurefConverter.toDMS(lat, isLat: true);
    final lonDms = TurefConverter.toDMS(lon, isLat: false);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle + başlık
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    Row(
                      children: [
                        const Text('📍', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        const Text(
                          'Nokta Koordinatları',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A9EFF).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF4A9EFF).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            'TUREF $dilim',
                            style: const TextStyle(
                              color: Color(0xFF4A9EFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onKapat,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.close, color: Colors.white54, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // TUREF TM koordinatları (ana bölüm)
          _SectionCard(
            label: 'TUREF / TM$dilim',
            color: const Color(0xFF4A9EFF),
            children: [
              _KoordRow(
                label: 'Doğu (E)',
                value: '${easting.toStringAsFixed(3)} m',
                copyValue: easting.toStringAsFixed(3),
              ),
              _KoordRow(
                label: 'Kuzey (N)',
                value: '${northing.toStringAsFixed(3)} m',
                copyValue: northing.toStringAsFixed(3),
              ),
              _KoordRow(
                label: 'Dilim',
                value: 'TM$dilim  (cm: $dilim° D)',
                copyValue: 'TM$dilim',
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Coğrafi koordinatlar
          _SectionCard(
            label: 'Coğrafi (TUREF / WGS84)',
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
            onTap: () => _copyAll(context, dilim, easting, northing, lat, lon),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
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
    );
  }

  void _copyAll(BuildContext ctx, int dilim, double e, double n, double lat, double lon) {
    final text = 'TUREF TM$dilim\nDoğu: ${e.toStringAsFixed(3)} m\nKuzey: ${n.toStringAsFixed(3)} m\n\nCoğrafi\nEnlem: ${lat.toStringAsFixed(8)}°\nBoylam: ${lon.toStringAsFixed(8)}°';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text('Koordinatlar kopyalandı'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String label;
  final Color color;
  final List<Widget> children;

  const _SectionCard({required this.label, required this.color, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
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
                Container(width: 3, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

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
          SnackBar(content: Text('$label kopyalandı'), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 1)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
                  if (subValue != null)
                    Text(subValue!, style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
                ],
              ),
            ),
            const Icon(Icons.copy, color: Colors.white12, size: 14),
          ],
        ),
      ),
    );
  }
}
