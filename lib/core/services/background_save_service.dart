import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/utils/api_error.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';
import 'package:simdaas/core/services/api_exception.dart';
import '../../main.dart' show appNavKey;

/// Runs a save action (Plot/Tractor/Control Unit create-or-update) to
/// completion regardless of whether the screen that started it is still
/// mounted. Pairs with BufferedSaveController (buffered_save_banner.dart),
/// which only controls what the ORIGINATING screen shows while the save is
/// in flight -- Discard there just stops that screen from watching/showing
/// the wait, it never touches this. Whatever screen the user ends up on,
/// they find out the result via a global snackbar (shown through the root
/// navigator, so it works even after navigating away).
class BackgroundSaveService {
  Future<void> run({
    required Future<void> Function() action,
    required String successMessage,
    Future<void> Function()? onSuccess,
    Future<void> Function(Object error)? onError,
    List<void Function()> onSettled = const [],
  }) async {
    try {
      await action();
      _showSuccess(successMessage);
      await onSuccess?.call();
    } catch (e) {
      _showError(e);
      await onError?.call(e);
    } finally {
      for (final cb in onSettled) {
        try {
          cb();
        } catch (_) {}
      }
    }
  }

  void _showSuccess(String message) {
    final ctx = appNavKey.currentContext;
    if (ctx == null) return;
    showSuccessSnackBar(ctx, message);
  }

  void _showError(Object e) {
    final ctx = appNavKey.currentContext;
    if (ctx == null) return;
    if (e is ApiException) {
      showApiErrorSnackBar(ctx, ApiError.fromResponse(e.statusCode, e.body));
    } else {
      showGenericErrorSnackBar(ctx, e.toString());
    }
  }
}

final backgroundSaveServiceProvider =
    Provider<BackgroundSaveService>((ref) => BackgroundSaveService());
