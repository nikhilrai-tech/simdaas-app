import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'platform_navigator_stub.dart'
    if (dart.library.html) 'platform_navigator_web.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class ConnectivityService {
  ConnectivityService() {
    debugPrint('ConnectivityService: created');
    _init();
  }

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _onlineController =
      StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityChanged => _onlineController.stream;
  Timer? _debounceTimer;
  int _consecutiveFailures = 0;
  DateTime? _lastProbeAt;
  String _lastProbeStatus = 'unknown';

  /// Timestamp of the last probe, or null if none yet.
  DateTime? get lastProbeAt => _lastProbeAt;

  /// Human-readable last probe status (e.g. 'ok' or error message)
  String get lastProbeStatus => _lastProbeStatus;

  /// Number of consecutive probe failures recorded by the service.
  int get consecutiveFailures => _consecutiveFailures;

  void _init() {
    debugPrint('ConnectivityService: initializing');
    // seed initial value with an active internet probe for accuracy
    _connectivity.checkConnectivity().then((res) async {
      debugPrint('ConnectivityService: initial connectivity -> $res');
      if (res == ConnectivityResult.none) {
        _consecutiveFailures = 0;
        debugPrint('ConnectivityService: connectivity NONE -> emitting false');
        _onlineController.add(false);
      } else {
        final ok = await _verifyInternet();
        _emitOnline(ok);
      }
    }).catchError((_) {
      _onlineController.add(false);
    });

    // listen for connectivity type changes; when a network becomes
    // available, perform a short verification probe to confirm internet
    // reachability. Use a small debounce to avoid spamming probes.
    _connectivity.onConnectivityChanged.listen((res) {
      debugPrint('ConnectivityService: onConnectivityChanged -> $res');
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
        if (res == ConnectivityResult.none) {
          _consecutiveFailures = 0;
          debugPrint(
              'ConnectivityService: connectivity NONE (onChange) -> emitting false');
          _onlineController.add(false);
        } else {
          final ok = await _verifyInternet();
          _emitOnline(ok);
        }
      });
    });
  }

  void _emitOnline(bool ok) {
    if (ok) {
      if (_consecutiveFailures > 0)
        debugPrint('ConnectivityService: probe succeeded, resetting failures');
      _consecutiveFailures = 0;
      debugPrint('ConnectivityService: emitting true (online)');
      _onlineController.add(true);
    } else {
      _consecutiveFailures++;
      debugPrint(
          'ConnectivityService: probe failed (count=$_consecutiveFailures)');
      // require two consecutive failures before reporting offline to avoid
      // transient network flakiness causing false offline state in the UI.
      if (_consecutiveFailures >= 2) {
        debugPrint(
            'ConnectivityService: emitting false (offline) after $_consecutiveFailures failures');
        _onlineController.add(false);
      } else {
        debugPrint(
            'ConnectivityService: waiting for another failure before emitting offline');
      }
    }
  }

  /// Trigger an immediate probe and emit a connectivity event.
  Future<void> probeNow() async {
    debugPrint('ConnectivityService: manual probeNow() requested');
    final ok = await _verifyInternet();
    _emitOnline(ok);
  }

  /// Lightweight internet probe. Returns true when a HEAD/GET to a known
  /// captive-portal-free endpoint succeeds within a short timeout.
  Future<bool> _verifyInternet(
      {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      // Try multiple lightweight endpoints to improve reachability
      // Primary: Google's generate_204 which returns 204 No Content if reachable
      final primary = Uri.parse('https://clients3.google.com/generate_204');
      try {
        debugPrint('ConnectivityService: probing $primary');
        final resp = await http.get(primary).timeout(timeout);
        debugPrint('ConnectivityService: probe $primary -> ${resp.statusCode}');
        _lastProbeAt = DateTime.now();
        _lastProbeStatus = 'primary:${resp.statusCode}';
        if (resp.statusCode == 204 || resp.statusCode == 200) return true;
      } catch (e) {
        _lastProbeAt = DateTime.now();
        _lastProbeStatus = 'primary_error:$e';
        debugPrint('ConnectivityService: probe primary failed: $e');
      }

      // Secondary: example.com (general reachable host)
      final secondary = Uri.parse('https://example.com/');
      try {
        debugPrint('ConnectivityService: probing $secondary');
        final resp = await http.get(secondary).timeout(timeout);
        debugPrint(
            'ConnectivityService: probe $secondary -> ${resp.statusCode}');
        _lastProbeAt = DateTime.now();
        _lastProbeStatus = 'secondary:${resp.statusCode}';
        if (resp.statusCode == 200) return true;
      } catch (e) {
        _lastProbeAt = DateTime.now();
        _lastProbeStatus = 'secondary_error:$e';
        debugPrint('ConnectivityService: probe secondary failed: $e');
      }

      // Platform-aware fallbacks. Raw DNS/socket operations are not supported
      // on web builds (they will throw UnsupportedOperation). Only attempt
      // these on non-web platforms.
      if (!kIsWeb) {
        // Fallback 1: DNS lookup. Some captive portals or restrictive
        // environments block HTTP but still resolve DNS. Try a DNS lookup
        // for example.com as a lightweight fallback.
        try {
          debugPrint(
              'ConnectivityService: attempting DNS lookup for example.com');
          final lookup = await InternetAddress.lookup('example.com')
              .timeout(const Duration(milliseconds: 1200));
          debugPrint('ConnectivityService: DNS lookup -> $lookup');
          if (lookup.isNotEmpty) {
            _lastProbeAt = DateTime.now();
            _lastProbeStatus = 'dns:${lookup.first.address}';
            return true;
          }
        } catch (e) {
          debugPrint('ConnectivityService: DNS lookup failed: $e');
          _lastProbeAt = DateTime.now();
          _lastProbeStatus = 'dns_error:$e';
        }

        // Fallback 2: TCP connect to a public DNS server (8.8.8.8:53).
        // This checks raw IP connectivity when HTTP/DNS resolution is blocked.
        try {
          debugPrint(
              'ConnectivityService: attempting socket connect to 8.8.8.8:53');
          final socket = await Socket.connect(InternetAddress('8.8.8.8'), 53,
              timeout: const Duration(milliseconds: 1500));
          socket.destroy();
          debugPrint('ConnectivityService: socket connect succeeded');
          _lastProbeAt = DateTime.now();
          _lastProbeStatus = 'socket:8.8.8.8:53';
          return true;
        } catch (e) {
          debugPrint('ConnectivityService: socket connect failed: $e');
          _lastProbeAt = DateTime.now();
          _lastProbeStatus = 'socket_error:$e';
        }
      } else {
        debugPrint(
            'ConnectivityService: running on web - attempting navigator.onLine fallback');
        try {
          final nav = navigatorIsOnline();
          debugPrint('ConnectivityService: navigator.onLine -> $nav');
          _lastProbeAt = DateTime.now();
          _lastProbeStatus = 'navigator:$nav';
          return nav;
        } catch (e) {
          debugPrint('ConnectivityService: navigator.onLine check failed: $e');
          _lastProbeAt = DateTime.now();
          _lastProbeStatus = 'navigator_error:$e';
        }
      }

      return false;
    } on SocketException catch (e) {
      debugPrint('ConnectivityService: socket exception: $e');
      return false;
    } on TimeoutException catch (e) {
      debugPrint('ConnectivityService: probe timeout: $e');
      return false;
    } catch (e) {
      debugPrint('ConnectivityService: probe error: $e');
      return false;
    }
  }

  Future<bool> checkOnline() async {
    try {
      final res = await _connectivity.checkConnectivity();
      if (res == ConnectivityResult.none) return false;
      return await _verifyInternet();
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    try {
      _onlineController.close();
    } catch (_) {}
    try {
      _debounceTimer?.cancel();
    } catch (_) {}
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final svc = ConnectivityService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

final isOnlineStreamProvider = StreamProvider<bool>((ref) {
  final svc = ref.watch(connectivityServiceProvider);
  return svc.onConnectivityChanged;
});
