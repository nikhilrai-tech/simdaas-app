import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/features/equipments/presentation/providers/equipment_providers.dart';

import '../../domain/entities/firmware_state.dart';
import '../providers/firmware_update_providers.dart';

/// How long the success banner stays up before auto-navigating back.
const Duration _kSuccessAutoBackDelay = Duration(seconds: 2);

/// Firmware Update Workspace (RFC-004 §3/§4/§5) — version handshake, then
/// the full OTA state-machine screen (progress bar, WiFi prompt, 90s
/// verification countdown, terminal success/failure/rollback banners).
class FirmwareUpdateWorkspaceScreen extends ConsumerStatefulWidget {
  const FirmwareUpdateWorkspaceScreen({
    super.key,
    required this.controlUnitId,
    required this.macAddress,
    required this.deviceName,
  });

  final String controlUnitId;
  final String macAddress;
  final String deviceName;

  @override
  ConsumerState<FirmwareUpdateWorkspaceScreen> createState() =>
      _FirmwareUpdateWorkspaceScreenState();
}

class _FirmwareUpdateWorkspaceScreenState
    extends ConsumerState<FirmwareUpdateWorkspaceScreen> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  ({String controlUnitId, String macAddress}) get _args =>
      (controlUnitId: widget.controlUnitId, macAddress: widget.macAddress);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firmwareUpdateControllerProvider(_args));
    final controller = ref.read(firmwareUpdateControllerProvider(_args).notifier);

    // On reaching SUCCESS, refresh the equipment lists (so the device detail
    // screen shows the new firmware_version once we're back on it) and
    // auto-navigate back after a couple seconds — no manual "Back" tap needed.
    ref.listen(firmwareUpdateControllerProvider(_args), (previous, next) {
      final wasSuccess = previous?.stage == FirmwareUpdateStage.success;
      if (next.stage == FirmwareUpdateStage.success && !wasSuccess) {
        final userId = ref.read(authServiceProvider).currentUserId;
        if (userId != null) {
          ref.invalidate(controlUnitsProvider(userId));
          ref.invalidate(equipmentsListProvider(userId));
        }
        Future.delayed(_kSuccessAutoBackDelay, () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text('Update Firmware — ${widget.deviceName}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildBody(context, state, controller),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, FirmwareUpdateState state,
      FirmwareUpdateController controller) {
    switch (state.stage) {
      case FirmwareUpdateStage.success:
        return _SuccessView(version: state.resultingVersion);
      case FirmwareUpdateStage.rollback:
        return _TerminalBanner(
          icon: Icons.settings_backup_restore,
          color: Colors.orange,
          message: state.errorReason ?? 'Unable to update. Please try again later.',
        );
      case FirmwareUpdateStage.criticalFailure:
        return _TerminalBanner(
          icon: Icons.error_outline,
          color: Colors.red,
          message: state.errorReason ??
              'Unable to update at this time. Please try after some time.',
        );
      case FirmwareUpdateStage.locked:
        return _LockedView(snapshot: state.snapshot);
      case FirmwareUpdateStage.wifiRequired:
      case FirmwareUpdateStage.wifiTimeout:
        return _WifiPromptView(
          state: state,
          controller: controller,
          ssidController: _ssidController,
          passwordController: _passwordController,
        );
      case FirmwareUpdateStage.downloading:
        return _ProgressView(percent: state.progressPercent ?? 0);
      case FirmwareUpdateStage.verifying:
        return _VerifyingView(secondsRemaining: state.verifyCountdownSeconds);
      case FirmwareUpdateStage.connectionLost:
        return _ConnectionLostView(controller: controller);
      case FirmwareUpdateStage.waitingToConnect:
        return const _WaitingView();
      case FirmwareUpdateStage.idle:
        return _HandshakeView(state: state, controller: controller);
    }
  }
}

class _HandshakeView extends StatelessWidget {
  const _HandshakeView({required this.state, required this.controller});

  final FirmwareUpdateState state;
  final FirmwareUpdateController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot;
    final canUpdate = snapshot != null &&
        snapshot.updateAvailable &&
        snapshot.liveVersion != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VersionRow(label: 'Database Version', value: snapshot?.dbVersion),
        const SizedBox(height: 12),
        _VersionRow(
            label: 'Available Version', value: snapshot?.availableVersion ?? '—'),
        const SizedBox(height: 12),
        _VersionRow(
          label: 'Live Hardware Version',
          value: snapshot?.liveVersion,
          loading: state.isCheckingLiveVersion,
        ),
        if (state.liveVersionCheckTimedOut) ...[
          const SizedBox(height: 8),
          const Text(
            'Device did not respond. Make sure it is powered on and '
            'connected to the internet, then try again.',
            style: TextStyle(color: Colors.red, fontSize: 13),
          ),
        ],
        const Spacer(),
        if (snapshot != null && snapshot.liveVersion == null)
          OutlinedButton(
            onPressed: state.isCheckingLiveVersion ? null : controller.checkVersion,
            child: Text(state.isCheckingLiveVersion
                ? 'Checking...'
                : state.liveVersionCheckTimedOut
                    ? 'Retry'
                    : 'Check Live Version'),
          ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: canUpdate ? controller.startUpdate : null,
          child: const Text('Update'),
        ),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, this.value, this.loading = false});

  final String label;
  final String? value;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        loading
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(value ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _WaitingView extends StatelessWidget {
  const _WaitingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Waiting to Connect...'),
        ],
      ),
    );
  }
}

class _WifiPromptView extends StatelessWidget {
  const _WifiPromptView({
    required this.state,
    required this.controller,
    required this.ssidController,
    required this.passwordController,
  });

  final FirmwareUpdateState state;
  final FirmwareUpdateController controller;
  final TextEditingController ssidController;
  final TextEditingController passwordController;

  @override
  Widget build(BuildContext context) {
    final isTimeout = state.stage == FirmwareUpdateStage.wifiTimeout;
    final disabled = state.isSubmittingWifi;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('WiFi credentials are needed to start the update.',
            style: TextStyle(fontSize: 16)),
        if (isTimeout) ...[
          const SizedBox(height: 12),
          Text(state.errorReason ?? 'Wi-Fi ID or Password is wrong. Please enter again.',
              style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: ssidController,
          enabled: !disabled,
          decoration: const InputDecoration(
            labelText: 'Wi-Fi / Hotspot Name (SSID)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passwordController,
          enabled: !disabled,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: ssidController,
          builder: (context, ssidValue, _) {
            return ValueListenableBuilder<TextEditingValue>(
              valueListenable: passwordController,
              builder: (context, passwordValue, _) {
                final valid =
                    ssidValue.text.trim().isNotEmpty && passwordValue.text.isNotEmpty;
                return ElevatedButton(
                  onPressed: valid && !disabled
                      ? () => controller.submitWifiCredentials(
                          ssidValue.text.trim(), passwordValue.text)
                      : null,
                  child: Text(disabled ? 'Waiting...' : 'Update'),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(Colors.orange, Colors.green, percent / 100)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Downloading firmware… $percent%', style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 16,
            color: color,
            backgroundColor: color.withOpacity(0.15),
          ),
        ),
      ],
    );
  }
}

class _VerifyingView extends StatelessWidget {
  const _VerifyingView({required this.secondsRemaining});
  final int secondsRemaining;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hourglass_top, size: 48),
          const SizedBox(height: 16),
          const Text('Download Complete. Checking New Version...',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text('${secondsRemaining}s', style: const TextStyle(fontSize: 24)),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({this.version});
  final String? version;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          const Text('Firmware Updated Successfully!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          if (version != null) ...[
            const SizedBox(height: 8),
            Text('Now running v$version'),
          ],
        ],
      ),
    );
  }
}

class _TerminalBanner extends StatelessWidget {
  const _TerminalBanner({required this.icon, required this.color, required this.message});
  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 64),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

class _ConnectionLostView extends StatelessWidget {
  const _ConnectionLostView({required this.controller});
  final FirmwareUpdateController controller;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Connection Lost'),
          content: const Text('Connection lost. Please make sure the device and '
              'Wi-Fi hotspot are turned on and placed close to each other.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    });
    return Center(
      child: ElevatedButton(
        onPressed: controller.retryAfterConnectionLost,
        child: const Text('Update'),
      ),
    );
  }
}

class _LockedView extends StatelessWidget {
  const _LockedView({this.snapshot});
  final FirmwareVersionSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: null,
        child: Text('Too many failures. Try again later.'),
      ),
    );
  }
}
