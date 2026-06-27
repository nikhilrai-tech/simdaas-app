import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Live "you are here" marker layer for FlutterMap screens.
///
/// Silently shows nothing if permission is denied or GPS is off — the
/// explicit "center on me" actions on each screen surface a proper error
/// via [LocationService] separately, this layer is just the passive dot.
class MyLocationLayer extends StatefulWidget {
  const MyLocationLayer({super.key});

  @override
  State<MyLocationLayer> createState() => _MyLocationLayerState();
}

class _MyLocationLayerState extends State<MyLocationLayer> {
  LatLng? _position;
  StreamSubscription<Position>? _sub;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;

      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        ),
      ).listen((pos) {
        if (mounted) {
          setState(() => _position = LatLng(pos.latitude, pos.longitude));
        }
      });
    } catch (_) {
      // No live dot if location is unavailable.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position;
    if (pos == null) return const SizedBox.shrink();
    return MarkerLayer(markers: [
      Marker(
        point: pos,
        width: 22,
        height: 22,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      ),
    ]);
  }
}
