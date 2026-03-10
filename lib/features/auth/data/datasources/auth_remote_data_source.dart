import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:simdaas/core/services/api_service.dart';
import 'package:simdaas/core/services/api_exception.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> signIn(String usernameOrEmail, String password);
  Future<void> logout(String? token);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final ApiService api;
  AuthRemoteDataSourceImpl(this.api);

  @override
  Future<UserModel> signIn(String usernameOrEmail, String password) async {
    // Postman: POST /api/auth/login/ with { username, password } -> returns { access, refresh }
    final dataRaw = await api.postJson('/api/auth/login/',
        jsonBody: {'username': usernameOrEmail, 'password': password},
        requiresAuth: false);
    final data =
        (dataRaw is Map<String, dynamic>) ? dataRaw : <String, dynamic>{};
    if (data.isNotEmpty) {
      // user info may not be present; attempt to extract user_id from access token
      String id = '';
      if (data['access'] != null) {
        try {
          final token = data['access'] as String;
          final parts = token.split('.');
          if (parts.length == 3) {
            final payload = parts[1];
            final normalized = base64.normalize(payload);
            final decoded = utf8.decode(base64Url.decode(normalized));
            final Map payloadMap = json.decode(decoded) as Map<String, dynamic>;
            if (payloadMap.containsKey('user_id')) {
              id = payloadMap['user_id'].toString();
            }
          }
        } catch (e, st) {
          debugPrint('AuthRemoteDataSource.signIn: token decode failed: $e');
          debugPrint(st.toString());
        }
      }
      // If logging in with username, email field might be username string initially
      // The profile fetch later will get the actual email
      return UserModel(id: id, email: usernameOrEmail);
    }
    throw ApiException(null, 'Authentication failed', path: '/api/auth/login/');
  }

  @override
  Future<void> logout(String? token) async {
    // Expectation from Postman: POST /api/auth/logout/ with Authorization Bearer <access>
    // and body { refresh_token: "..." }
    if (token == null) return;
    // token here we assume is the access token; logout endpoint may need the refresh token in body
    await api.postJson('/api/auth/logout/',
        headers: {'Authorization': 'Bearer $token'});
  }
}
