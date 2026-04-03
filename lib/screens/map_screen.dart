import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../models/kml_feature.dart';
import '../services/kml_parser.dart';
import '../services/location_service.dart';
import '../widgets/info_bottom_sheet.dart';
import '../widgets/koordinat_panel.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final Set<Polygon> _polygons = {};

  List<KmlFeature> _features = [];
  String? _fileName;

  // GPS
  LatLng? _myLocation;
  StreamSubscription<Position>? _locationSub;
  bool _trackingEnabled = false;
  bool _locationLoading = false;

  // Paylaşım
  StreamSubscription? _sharingIntentSub;

  // Koordinat paneli
  LatLng? _tiklananNokta;

  static const _initialCamera = CameraPosition(
    target: LatLng(39.0, 35.0),
    zoom: 6,
  );

  @override
  void initState() {
    super.initState();
    _initSharingIntent();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _sharingIntentSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ─── WhatsApp / Paylaşım Intent ──────────────────────────
  void _initSharingIntent() {
    // Uygulama kapalıyken gelen dosya (cold start)
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handleSharedFiles(files);
    });

    // Uygulama açıkken gelen dosya (warm start)
    _sharingIntentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) => _handleSharedFiles(files),
    );
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final file = files.first;
    final path = file.path;
    if (path.isEmpty) return;

    try {
      final content = File(path).readAsStringSync();
      final name = path.split('/').last.split('\\').last;
      _loadKmlContent(content, name);
    } catch (e) {
      if (mounted) _showSnack('Dosya okunamadı: $e');
    }
  }

  // ─── KML Yükle (manuel seçim) ────────────────────────────
  Future<void> _pickKmlFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['kml'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    _loadKmlContent(String.fromCharCodes(bytes), file.name);
  }

  void _loadKmlContent(String content, String name) {
    try {
      final features = KmlParser.parse(content);
      if (!mounted) return;
      if (features.isEmpty) {
        _showSnack('KML dosyasında görüntülenebilir öğe bulunamadı.');
        return;
      }
      setState(() {
        _features = features;
        _fileName = name;
      });
      _buildMapOverlays();
      Future.delayed(const Duration(milliseconds: 300), _fitBounds);
    } catch (e) {
      if (mounted) _showSnack('KML okunamadı: $e');
    }
  }

  void _clearKml() {
    setState(() {
      _features = [];
      _fileName = null;
      _markers.removeWhere((m) => m.markerId.value != 'my_location');
      _polylines.clear();
      _polygons.clear();
    });
  }

  void _onMapTap(LatLng nokta) {
    setState(() => _tiklananNokta = nokta);
  }

  // ─── Harita Overlay ──────────────────────────────────────
  void _buildMapOverlays() {
    _markers.removeWhere((m) => m.markerId.value != 'my_location');
    _polylines.clear();
    _polygons.clear();

    for (int i = 0; i < _features.length; i++) {
      final f = _features[i];
      final strokeColor = _hexToColor(f.style.strokeColor ?? '#FF4444');
      final fillColor = _hexToColor(f.style.fillColor ?? '#FF4444')
          .withValues(alpha: f.style.fillOpacity);

      switch (f.type) {
        case KmlGeometryType.point:
          if (f.points.isEmpty) break;
          _markers.add(Marker(
            markerId: MarkerId('feature_$i'),
            position: f.points.first,
            infoWindow: InfoWindow(
              title: f.name ?? 'Özellik',
              snippet: f.description != null ? _stripHtml(f.description!) : null,
            ),
          ));

        case KmlGeometryType.lineString:
          _polylines.add(Polyline(
            polylineId: PolylineId('line_$i'),
            points: f.points,
            color: strokeColor,
            width: f.style.strokeWidth.round().clamp(1, 20),
            consumeTapEvents: true,
            onTap: () => _showFeatureSheet(f),
          ));

        case KmlGeometryType.polygon:
          _polygons.add(Polygon(
            polygonId: PolygonId('poly_$i'),
            points: f.rings.isNotEmpty ? f.rings.first : [],
            holes: f.rings.length > 1 ? f.rings.sublist(1) : [],
            strokeColor: strokeColor,
            strokeWidth: f.style.strokeWidth.round().clamp(1, 20),
            fillColor: fillColor,
            consumeTapEvents: true,
            onTap: () => _showFeatureSheet(f),
          ));

        case KmlGeometryType.unknown:
          break;
      }
    }
    setState(() {});
  }

  void _fitBounds() {
    if (_mapController == null || _features.isEmpty) return;
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final f in _features) {
      for (final p in [...f.points, ...f.rings.expand((r) => r)]) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
    }
    if (minLat > maxLat) return;
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  // ─── GPS ─────────────────────────────────────────────────
  Future<void> _toggleTracking() async {
    if (_trackingEnabled) {
      _locationSub?.cancel();
      setState(() => _trackingEnabled = false);
      return;
    }
    setState(() => _locationLoading = true);
    final granted = await LocationService.requestPermission();
    if (!granted) {
      if (mounted) {
        setState(() => _locationLoading = false);
        _showSnack('Konum izni verilmedi.');
      }
      return;
    }
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    if (pos != null) {
      final latlng = LatLng(pos.latitude, pos.longitude);
      _updateMyLocation(latlng);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latlng, 15));
    }
    _locationSub = LocationService.trackPosition().listen((pos) {
      if (!mounted) return;
      _updateMyLocation(LatLng(pos.latitude, pos.longitude));
    });
    setState(() { _trackingEnabled = true; _locationLoading = false; });
  }

  void _updateMyLocation(LatLng latlng) {
    setState(() {
      _myLocation = latlng;
      _markers.removeWhere((m) => m.markerId.value == 'my_location');
      _markers.add(Marker(
        markerId: const MarkerId('my_location'),
        position: latlng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Konumunuz'),
        zIndex: 99,
      ));
    });
  }

  void _goToMyLocation() {
    if (_myLocation == null) return;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_myLocation!, 16));
  }

  // ─── Yardımcılar ─────────────────────────────────────────
  Color _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) return Color(int.parse('FF$clean', radix: 16));
    return const Color(0xFFFF4444);
  }

  String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), '').trim();

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  void _showFeatureSheet(KmlFeature feature) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => InfoBottomSheet(feature: feature),
    );
  }

  // ─── Build ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCamera,
            mapType: MapType.satellite,
            markers: _markers,
            polylines: _polylines,
            polygons: _polygons,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: false,
            onTap: _onMapTap,
            onMapCreated: (ctrl) {
              _mapController = ctrl;
              if (_features.isNotEmpty) _fitBounds();
            },
          ),

          // Üst Bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: _buildTopBar(),
          ),

          // Sağ Kontroller
          Positioned(
            right: 12,
            bottom: 40,
            child: _buildSideControls(),
          ),

          // Koordinat paneli — haritaya tıklanınca
          if (_tiklananNokta != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: KoordinatPanel(
                nokta: _tiklananNokta!,
                onKapat: () => setState(() => _tiklananNokta = null),
              ),
            ),

          // Başlangıç ekranı — KML yüklenmemişse
          if (_features.isEmpty)
            Positioned.fill(
              child: _buildWelcomeOverlay(),
            ),
        ],
      ),
    );
  }

  Widget _buildWelcomeOverlay() {
    return IgnorePointer(
      ignoring: false,
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xF00A0A18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🌍', style: TextStyle(fontSize: 52)),
                const SizedBox(height: 12),
                const Text(
                  'KeMaL',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 2),
                ),
                const SizedBox(height: 6),
                Text(
                  'Harita Görüntüleyici',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5), letterSpacing: 1),
                ),
                const SizedBox(height: 28),
                GestureDetector(
                  onTap: _pickKmlFile,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A9EFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('KML Dosyası Seç', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'veya WhatsApp\'tan bir .kml dosyası paylaşın',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45), height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xEE0A0A18),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8)],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Text('🌍', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          const Text('KeMaL', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          const SizedBox(width: 8),
          if (_fileName != null) ...[
            Container(width: 1, height: 20, color: Colors.white12),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _fileName!,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0x334A9EFF),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0x554A9EFF)),
              ),
              child: Text('${_features.length}', style: const TextStyle(color: Color(0xFF4A9EFF), fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _clearKml,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.close, color: Colors.white38, size: 16),
              ),
            ),
          ] else
            const Spacer(),
          GestureDetector(
            onTap: _pickKmlFile,
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF4A9EFF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open, color: Colors.white, size: 15),
                  SizedBox(width: 4),
                  Text('KML', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _mapBtn(icon: Icons.add, onTap: () => _mapController?.animateCamera(CameraUpdate.zoomIn())),
        const SizedBox(height: 6),
        _mapBtn(icon: Icons.remove, onTap: () => _mapController?.animateCamera(CameraUpdate.zoomOut())),
        if (_features.isNotEmpty) ...[
          const SizedBox(height: 6),
          _mapBtn(icon: Icons.fit_screen, onTap: _fitBounds, tooltip: 'Tümünü Göster'),
        ],
        const SizedBox(height: 6),
        _mapBtn(
          icon: _trackingEnabled ? Icons.gps_fixed : Icons.gps_not_fixed,
          color: _trackingEnabled ? const Color(0xFF4A9EFF) : null,
          onTap: _locationLoading ? null : _toggleTracking,
          loading: _locationLoading,
        ),
        if (_myLocation != null) ...[
          const SizedBox(height: 6),
          _mapBtn(icon: Icons.my_location, onTap: _goToMyLocation),
        ],
      ],
    );
  }

  Widget _mapBtn({required IconData icon, VoidCallback? onTap, Color? color, bool loading = false, String? tooltip}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          color: const Color(0xEE0F0F1E),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6)],
        ),
        child: loading
            ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4A9EFF)))
            : Icon(icon, color: color ?? Colors.white, size: 22),
      ),
    );
  }
}
