import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/connectivity_service.dart';

class ConnectivityDebugOverlay extends ConsumerWidget {
  const ConnectivityDebugOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) return const SizedBox.shrink();

    final asyncOnline = ref.watch(isOnlineStreamProvider);
    final svc = ref.read(connectivityServiceProvider);

    String onlineText = 'unknown';
    Color dotColor = Colors.grey;
    asyncOnline.when(
      data: (val) {
        onlineText = val ? 'ONLINE' : 'OFFLINE';
        dotColor = val ? Colors.green : Colors.red;
      },
      loading: () {
        onlineText = 'probing...';
        dotColor = Colors.orange;
      },
      error: (e, st) {
        onlineText = 'error';
        dotColor = Colors.grey;
      },
    );

    final lastProbe = svc.lastProbeAt != null
        ? '${svc.lastProbeAt} (${svc.lastProbeStatus})'
        : 'none';

    return Positioned(
      right: 12,
      top: 40,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          width: 220,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    onlineText,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Failures: ${svc.consecutiveFailures}',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(height: 4),
              Text('Last probe: $lastProbe',
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () => svc.probeNow(),
                    child: const Text('Probe now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey,
                      minimumSize: const Size(80, 32),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      // quick connectivity check
                      final ok = await svc.checkOnline();
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('checkOnline -> $ok')));
                    },
                    child: const Text('Check'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      minimumSize: const Size(60, 32),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
