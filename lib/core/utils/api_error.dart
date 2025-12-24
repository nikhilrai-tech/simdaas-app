import 'dart:convert';

class ApiError {
  final int? status;
  final Map<String, dynamic>? bodyMap;

  ApiError({this.status, this.bodyMap});

  /// Parse raw response body into ApiError. If body isn't JSON, put it
  /// under 'detail' so callers still have a message.
  static ApiError fromResponse(int? status, String? body) {
    if (body == null) return ApiError(status: status);
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        return ApiError(status: status, bodyMap: decoded);
      }
      // If API returned a non-map JSON (string/array), wrap it
      return ApiError(status: status, bodyMap: {'detail': decoded.toString()});
    } catch (_) {
      return ApiError(status: status, bodyMap: {'detail': body});
    }
  }

  /// Return the most useful human-readable message available in the body.
  /// Strategy:
  /// 1. If a map of field -> [messages], pick the first message across keys.
  /// 2. If a 'detail' string exists, return it.
  /// 3. Fallback to a generic message.
  String firstMessage() {
    if (bodyMap == null || bodyMap!.isEmpty) return 'An error occurred';
    try {
      // Prefer field validation messages (list/string)
      for (final entry in bodyMap!.entries) {
        final v = entry.value;
        if (v is List && v.isNotEmpty) return v.first.toString();
        if (v is String && v.isNotEmpty) return v;
      }
      // fallback to 'detail' or first value
      if (bodyMap!.containsKey('detail')) return bodyMap!['detail'].toString();
      final first = bodyMap!.values.first;
      return first?.toString() ?? 'An error occurred';
    } catch (_) {
      return 'An error occurred';
    }
  }

  /// Return a combined message joining field keys and messages. Useful when
  /// you want to show all validation issues at once.
  String combinedMessages([String separator = ' • ']) {
    if (bodyMap == null || bodyMap!.isEmpty) return 'An error occurred';
    final msgs = <String>[];
    bodyMap!.forEach((k, v) {
      if (v is List && v.isNotEmpty) {
        msgs.add('$k: ${v.join(', ')}');
      } else {
        msgs.add('$k: ${v.toString()}');
      }
    });
    return msgs.join(separator);
  }
}
