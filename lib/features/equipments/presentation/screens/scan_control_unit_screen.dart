import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';

class ScanControlUnitScreen extends StatefulWidget {
  const ScanControlUnitScreen({super.key});

  @override
  State<ScanControlUnitScreen> createState() => _ScanControlUnitScreenState();
}

class _ScanControlUnitScreenState extends State<ScanControlUnitScreen> {
  bool _scanned = false;

  void _handleQr(String value) {
    if (_scanned) return;
    _scanned = true;
    try {
      final Map<String, dynamic> data = json.decode(value);
      // Normalize keys (example QR has ID, Name, User, Mac Address)
      final existing = <String, dynamic>{
        'category': 'control_unit',
        'controlUnitId':
            data['ID'] ?? data['Id'] ?? data['id'] ?? data['controlUnitId'],
        'name': data['Name'] ?? data['name'] ?? data['Name'] ?? '',
        'userId': data['User'] ?? data['user'] ?? '',
        'macAddress': data['Mac Address'] ??
            data['MAC Address'] ??
            data['Mac'] ??
            data['mac'] ??
            '',
      };
      Navigator.of(context).pop(existing);
    } catch (_) {
      // QR is plain text — treat the raw value as a MAC address
      Navigator.of(context).pop(<String, dynamic>{
        'category': 'control_unit',
        'macAddress': value.trim(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Control Unit')),
      body: MobileScanner(
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue;
            if (raw != null) {
              _handleQr(raw);
              break;
            }
          }
        },
      ),
    );
  }
}
