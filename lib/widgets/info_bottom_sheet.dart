import 'package:flutter/material.dart';
import '../models/kml_feature.dart';

class InfoBottomSheet extends StatelessWidget {
  final KmlFeature feature;

  const InfoBottomSheet({super.key, required this.feature});

  String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), '').trim();

  @override
  Widget build(BuildContext context) {
    final name = feature.name;
    final desc = feature.description != null ? _stripHtml(feature.description!) : null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (name != null && name.isNotEmpty) ...[
            Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
          ],
          if (desc != null && desc.isNotEmpty)
            Text(desc, style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5))
          else if (name == null || name.isEmpty)
            Text('Özellik bilgisi yok', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
