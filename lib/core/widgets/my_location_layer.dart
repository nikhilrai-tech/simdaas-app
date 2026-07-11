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
  /// Called with every position emitted by this layer's own GPS stream, so
  /// callers (e.g. a "center on me" button) can reuse the live fix instead
  /// of starting a second, competing one-shot location request -- running
  /// two concurrent location requests on the same screen has been observed
  /// to make Android starve one of them indefinitely on some OEM devices.
  final void Function(LatLng position)? onPosition;

  const MyLocationLayer({super.key, this.onPosition});

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
        final latLng = LatLng(pos.latitude, pos.longitude);
        widget.onPosition?.call(latLng);
        if (mounted) {
          setState(() => _position = latLng);
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
