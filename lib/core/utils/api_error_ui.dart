import 'package:flutter/material.dart';
import 'api_error.dart';

/// Show a SnackBar for an [ApiError] with consistent styling.
void showApiErrorSnackBar(BuildContext context, ApiError err,
    {bool isWarning = false}) {
  final message = err.firstMessage();
  final color = isWarning ? Colors.orange : Colors.red;
  final snack = SnackBar(
    content: Row(children: [
      Icon(isWarning ? Icons.warning : Icons.error, color: Colors.white),
      const SizedBox(width: 12),
      Expanded(child: Text(message)),
    ]),
    backgroundColor: color,
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 4),
  );
  try {
    ScaffoldMessenger.of(context).showSnackBar(snack);
  } catch (_) {}
}

/// Show a generic error message when an ApiError isn't available.
void showGenericErrorSnackBar(BuildContext context, String message,
    {bool isWarning = false}) {
  final color = isWarning ? Colors.orange : Colors.red;
  final snack = SnackBar(
    content: Row(children: [
      Icon(isWarning ? Icons.warning : Icons.error, color: Colors.white),
      const SizedBox(width: 12),
      Expanded(child: Text(message)),
    ]),
    backgroundColor: color,
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 4),
  );
  try {
    ScaffoldMessenger.of(context).showSnackBar(snack);
  } catch (_) {}
}

/// Show an informational SnackBar (blue) for non-error messages.
void showInfoSnackBar(BuildContext context, String message) {
  final snack = SnackBar(
    content: Row(children: [
      Icon(Icons.info_outline, color: Colors.white),
      const SizedBox(width: 12),
      Expanded(child: Text(message)),
    ]),
    backgroundColor: Colors.blue,
    behavior: SnackBarBehavior.floating,
  );
  try {
    ScaffoldMessenger.of(context).showSnackBar(snack);
  } catch (_) {}
}

/// Show a success SnackBar (green) for confirmations.
void showSuccessSnackBar(BuildContext context, String message) {
  final snack = SnackBar(
    content: Row(children: [
      Icon(Icons.check_circle_outline, color: Colors.white),
      const SizedBox(width: 12),
      Expanded(child: Text(message)),
    ]),
    backgroundColor: Colors.green,
    behavior: SnackBarBehavior.floating,
  );
  try {
    ScaffoldMessenger.of(context).showSnackBar(snack);
  } catch (_) {}
}
