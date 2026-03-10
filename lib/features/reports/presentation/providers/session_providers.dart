import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/api_service.dart';
import 'package:simdaas/core/services/auth_service.dart';

final activeSessionsListProvider = FutureProvider<List<dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    final response = await api.getJson('/jobs/api/sessions/');
    debugPrint('activeSessionsListProvider: raw response type: ${response.runtimeType}');
    if (response is List) {
      debugPrint('activeSessionsListProvider: count: ${response.length}');
      if (response.isNotEmpty) {
        debugPrint('activeSessionsListProvider: first item status: ${response.first['status']}');
      }
      // Filter for only active sessions
      final filtered = response.where((s) => s['status'] == 'active').toList();
      debugPrint('activeSessionsListProvider: filtered count: ${filtered.length}');
      return filtered;
    } else {
      debugPrint('activeSessionsListProvider: response is NOT a list: $response');
    }
  } catch (e) {
    debugPrint('activeSessionsListProvider: error: $e');
  }
  return [];
});
