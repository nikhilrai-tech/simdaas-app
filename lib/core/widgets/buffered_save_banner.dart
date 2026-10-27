import 'dart:async';
import 'package:flutter/material.dart';

/// Local, per-screen tracker for one in-flight save. Pairs with
/// BackgroundSaveService (core/services/background_save_service.dart), which
/// guarantees the save itself runs to completion and notifies the user
/// globally regardless of this screen's lifecycle -- this class only
/// controls what THIS screen shows while it's still around to show anything:
/// a "Saving…" banner that gains a Discard action after [showDiscardAfter]
/// if the save is still running.
///
/// Discard only stops this screen from watching/displaying the wait -- it
/// never cancels the underlying save (there is no reliable way to cancel an
/// HTTP request that may have already reached the server; BackgroundSaveService
/// keeps running it regardless and reports the eventual result globally).
class BufferedSaveController extends ChangeNotifier {
  BufferedSaveController({this.showDiscardAfter = const Duration(seconds: 4)});

  final Duration showDiscardAfter;
  bool isSaving = false;
  bool showDiscard = false;
  bool _dismissed = false;
  Timer? _discardTimer;

  bool get isVisible => isSaving && !_dismissed;

  /// Call right when the save is kicked off via BackgroundSaveService --
  /// this screen does not await that call directly, so it can still react
  /// (this banner) while the save itself is independent of this screen.
  void start() {
    isSaving = true;
    showDiscard = false;
    _dismissed = false;
    _discardTimer?.cancel();
    _discardTimer = Timer(showDiscardAfter, () {
      showDiscard = true;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Call when the save actually completes (success or error) -- safe to
  /// call even after the user already discarded/dismissed the banner.
  void finish() {
    isSaving = false;
    _discardTimer?.cancel();
    notifyListeners();
  }

  /// User tapped Discard: stop showing the wait on this screen. The save
  /// itself is untouched -- BackgroundSaveService still runs it to
  /// completion and shows the eventual result via a global snackbar.
  void discard() {
    _dismissed = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _discardTimer?.cancel();
    super.dispose();
  }
}

/// The "Saving…" / "Saving… [Discard]" banner. Place at the top of a Stack
/// (or as a persistent header) on any Create/Edit screen using
/// [BufferedSaveController].
class BufferedSaveBanner extends StatelessWidget {
  const BufferedSaveBanner({
    super.key,
    required this.controller,
    this.label = 'Saving…',
  });

  final BufferedSaveController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isVisible) return const SizedBox.shrink();
        return Material(
          color: Colors.blueGrey.shade800,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                  if (controller.showDiscard)
                    TextButton(
                      onPressed: controller.discard,
                      child: const Text('Discard',
                          style: TextStyle(color: Colors.amberAccent)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
