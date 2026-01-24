import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:simdaas/core/services/api_service.dart';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/services/auth_service.dart';

// NOTE: This file was originally Firestore-backed. It now uses the REST API
// via `ApiService` (provided by `apiServiceProvider`). The providers return
// plain Maps containing an `id` key so existing UI that expects either
// QueryDocumentSnapshot or Map will continue to work.

/// Simple users controller that exposes listing and creation helpers using REST.
class UsersController {
  final Ref ref;
  UsersController(this.ref);

  ApiService get _api => ref.read(apiServiceProvider);

  /// Returns a list of user maps. Each map contains an `id` key.
  Future<List<Map<String, dynamic>>> listUsers() async {
    try {
      // Canonical endpoint (required): list of users
      final dr = await _api.getJson('/api/users/');
      if (dr == null) {
        throw ApiException(null, 'Empty response from /api/users/');
      }
      if (dr is! List) {
        throw ApiException(null, 'Unexpected response type from /api/users/');
      }
      final arr = dr;
      final out = <Map<String, dynamic>>[];
      for (final item in arr) {
        final map = Map<String, dynamic>.from(item);
        final id = (map['id']?.toString() ?? map['pk']?.toString() ?? '');
        map['id'] = id;
        out.add(map);
      }
      // no debug logging
      return out;
    } catch (e, st) {
      // Log and surface error to callers
      debugPrint('UsersController.listUsers error: $e\n$st');
      rethrow;
    }
  }

  /// Fetch a single user by id using REST endpoints if available.
  /// Returns null when the user cannot be found or on error.
  Future<Map<String, dynamic>?> getUserById(String id) async {
    try {
      // Canonical endpoint: fetch single user by id
      final dr = await _api.getJson('/api/users/$id/');
      if (dr == null) return null;
      if (dr is List && dr.isNotEmpty) {
        final map = Map<String, dynamic>.from(dr.first);
        final uid = (map['id']?.toString() ?? map['pk']?.toString() ?? '');
        map['id'] = uid;
        return map;
      }
      if (dr is Map) {
        final map = Map<String, dynamic>.from(dr);
        final uid = (map['id']?.toString() ?? map['pk']?.toString() ?? '');
        map['id'] = uid;
        return map;
      }
      return null;
    } catch (e, st) {
      debugPrint('UsersController.getUserById error: $e\n$st');
      return null;
    }
  }

  /// Create a new user via the REST API. Returns the created user's id if
  /// available.
  Future<String> createUser(
      {required String email,
      required String password,
      required String name,
      String? phone,
      List<String>? roles}) async {
    final bodyMap = {
      'email': email,
      'password': password,
      'name': name,
      'phone': phone ?? '',
      'roles': roles ?? ['operator']
    };
    final dr = await _api.postJson('/api/users/', jsonBody: bodyMap);
    ref.invalidate(usersListProvider);
    if (dr is Map) {
      final id = (dr['id']?.toString() ?? dr['pk']?.toString() ?? '');
      return id;
    }
    throw ApiException(null, 'Create user failed');
  }
}

final usersControllerProvider = Provider((ref) => UsersController(ref));

/// Operators collection (simple list + create helper) via REST.
class OperatorsController {
  final Ref ref;
  OperatorsController(this.ref);

  ApiService get _api => ref.read(apiServiceProvider);

  Future<List<Map<String, dynamic>>> listOperators() async {
    try {
      // Canonical endpoint for operators
      final dr = await _api.getJson('/api/operators/');
      if (dr == null) {
        throw ApiException(null, 'Empty response from /api/operators/');
      }
      if (dr is! List) {
        throw ApiException(
            null, 'Unexpected response type from /api/operators/');
      }
      final arr = dr;
      final out = <Map<String, dynamic>>[];
      for (final item in arr) {
        final map = Map<String, dynamic>.from(item);
        // normalize snake_case -> camelCase for UI
        if (map.containsKey('contact_number')) {
          map['phone'] = map['contact_number'];
        }
        if (map.containsKey('experience_years')) {
          map['experienceYears'] = map['experience_years'];
        }
        final id = (map['id']?.toString() ?? map['pk']?.toString() ?? '');
        map['id'] = id;
        out.add(map);
      }
      return out;
    } catch (e, st) {
      // Log and rethrow; callers (providers) will show errors
      debugPrint('OperatorsController.listOperators error: $e\n$st');
      rethrow;
    }
  }

  /// Create an operator. Accepts the full set of fields the backend
  /// expects (snake_case keys are constructed here).
  Future<String> createOperator({
    required String name,
    String? contactNumber,
    String? email,
    String? address,
    int? experienceYears,
    String? assignedMachine,
    String? shiftTiming,
    bool? isActive,
  }) async {
    final bodyMap = <String, dynamic>{
      'name': name,
      'contact_number': contactNumber ?? '',
      'email': email ?? '',
      'address': address ?? '',
      'experience_years': experienceYears ?? 0,
      'assigned_machine': assignedMachine ?? '',
      'shift_timing': shiftTiming ?? '',
      'is_active': isActive ?? true,
    };

    final dr = await _api.postJson('/api/operators/', jsonBody: bodyMap);
    ref.invalidate(operatorsListProvider);
    if (dr is Map) {
      final id = (dr['id']?.toString() ?? dr['pk']?.toString() ?? '');
      return id;
    }
    throw ApiException(null, 'Create operator failed');
  }
}

final operatorsControllerProvider = Provider((ref) => OperatorsController(ref));

final operatorsListProvider = FutureProvider((ref) async {
  final ctrl = ref.read(operatorsControllerProvider);
  final ops = await ctrl.listOperators();
  return ops;
});

// Users list provider: return an empty list on error so screens that display
// jobs (which also try to resolve user names) don't fail when the users
// endpoint is unavailable. The controller still exposes errors to callers
// that want to surface them explicitly.
final usersListProvider = FutureProvider((ref) async {
  final ctrl = ref.read(usersControllerProvider);
  try {
    final users = await ctrl.listUsers();
    return users;
  } catch (e, st) {
    // ignore: avoid_print
    debugPrint('usersListProvider: failed to load users: $e\n$st');
    return <Map<String, dynamic>>[];
  }
});

/// Fetch a single user by id. Returns null when not found.
final userByIdProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, id) async {
  final ctrl = ref.read(usersControllerProvider);
  try {
    final u = await ctrl.getUserById(id);
    return u;
  } catch (e) {
    return null;
  }
});
