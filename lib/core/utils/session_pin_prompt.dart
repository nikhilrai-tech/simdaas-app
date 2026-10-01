import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:simdaas/core/services/api_exception.dart';

/// Thrown when the user backs out of the session-PIN prompt -- caught by the
/// caller to abort the action quietly, not as an error.
class PinCancelled implements Exception {}

/// Backend errors for a session-PIN-gated endpoint carry a stable `code`
/// ("pin_required" / "invalid_pin" -- see tools.views._check_session_pin).
String? sessionPinErrorCode(Object err) {
  if (err is! ApiException || err.body == null) return null;
  try {
    final body = json.decode(err.body!);
    if (body is Map) return body['code']?.toString();
  } catch (_) {}
  return null;
}

Future<String?> promptSessionPin(
  BuildContext context, {
  required String message,
  String? errorText,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Enter Session PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: 'PIN',
              errorText: errorText,
              counterText: '',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}

/// Tries [action] with no PIN first (the common case: no PIN set for this
/// user -- see userauth/admin.py). If the backend replies pin_required/
/// invalid_pin, prompts for the session PIN and retries, looping on a wrong
/// entry. Throws [PinCancelled] if the user backs out of the prompt.
///
/// Shared by every screen that calls a session-PIN-gated endpoint (session
/// mode switching, heatmap color-band preferences) so they all show the
/// exact same PIN dialog rather than each reimplementing it.
///
/// [isMounted] should return the calling State's `mounted` getter -- checked
/// after each await, since this runs across multiple awaited gaps.
Future<T> runWithPinRetry<T>(
  BuildContext context, {
  required Future<T> Function(String? pin) action,
  required bool Function() isMounted,
  String promptMessage = 'This action requires a PIN.',
}) async {
  String? pin;
  while (true) {
    try {
      return await action(pin);
    } on ApiException catch (err) {
      final code = sessionPinErrorCode(err);
      if (code != 'pin_required' && code != 'invalid_pin') rethrow;
      if (!isMounted()) throw PinCancelled();
      final entered = await promptSessionPin(
        context,
        message: promptMessage,
        errorText: code == 'invalid_pin' ? 'Incorrect PIN. Try again.' : null,
      );
      if (entered == null || entered.isEmpty) throw PinCancelled();
      pin = entered;
    }
  }
}
