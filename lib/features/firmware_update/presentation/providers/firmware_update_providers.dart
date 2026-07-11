import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/services/telemetry_service.dart';
import '../../data/datasources/firmware_remote_data_source.dart';
import '../../data/repositories/firmware_repository_impl.dart';
import '../../domain/entities/firmware_state.dart';

final firmwareRepoProvider = Provider((ref) => FirmwareRepositoryImpl(
    FirmwareRemoteDataSourceImpl(ref.read(apiServiceProvider))));

/// Backs the Alerts tab in admin_dashboard_screen.dart (RFC-004 §2.3/§4.5).
final firmwareAlertsProvider = FutureProvider<List<FirmwareAlertEntity>>((ref) async {
  final repo = ref.read(firmwareRepoProvider);
  return repo.getAdminAlerts();
});

/// Server-side 504 lockout (RFC-004 §2.2.1) — the app-local countdown
/// (RFC-004 §8.2, hardware spec Path B) is a UI convenience layered on top,
/// not the enforcement boundary.
const int kMax504StreakBeforeLocalDisable = 5;
const Duration kLocalLockoutDuration = Duration(hours: 1);

/// If the device doesn't reply to a version query within this window, stop
/// spinning and show a "device not responding" state instead — a genuinely
/// offline/unpowered device would otherwise spin forever, since there is no
/// MQTT-level timeout/NACK for a query nobody answers.
const Duration kLiveVersionCheckTimeout = Duration(seconds: 20);

/// How often to poll the REST snapshot as a safety net while a stage is
/// "active" (waitingToConnect/downloading/verifying) — catches the UI up if
/// a WebSocket status event was ever missed (a real phone can briefly lose
/// its socket mid-update — backgrounding, network switch — unlike the
/// always-on dev/web session this feature was mostly tested against).
const Duration kResyncPollInterval = Duration(seconds: 8);

const _kActiveStages = {
  FirmwareUpdateStage.waitingToConnect,
  FirmwareUpdateStage.downloading,
  FirmwareUpdateStage.verifying,
};

/// Maps a backend-persisted OTA status onto the *terminal* UI stage it
/// implies, or null if it's not a terminal status (WIFI_CONNECTING/
/// IN_PROGRESS/DOWNLOAD_OK/IDLE all still need a live event to resolve).
FirmwareUpdateStage? _terminalStageForBackendStatus(String? status, int? code) {
  switch (status) {
    case 'SUCCESS':
      return FirmwareUpdateStage.success;
    case 'ROLLBACK':
      return FirmwareUpdateStage.rollback;
    case 'FAILED':
      switch (code) {
        case 401:
          return FirmwareUpdateStage.wifiRequired;
        case 408:
          return FirmwareUpdateStage.wifiTimeout;
        case 504:
          return FirmwareUpdateStage.connectionLost;
        default:
          return FirmwareUpdateStage.criticalFailure;
      }
    default:
      return null;
  }
}

class FirmwareUpdateState {
  final FirmwareUpdateStage stage;
  final FirmwareVersionSnapshot? snapshot;
  final int? progressPercent;
  final String? errorReason;
  final int verifyCountdownSeconds; // ticks down from 90 on DOWNLOAD_OK
  final int consecutive504Count;
  final DateTime? localLockUntil;
  final String? resultingVersion;
  final bool isSubmittingWifi;
  final bool isCheckingLiveVersion;
  final bool liveVersionCheckTimedOut;

  const FirmwareUpdateState({
    this.stage = FirmwareUpdateStage.idle,
    this.snapshot,
    this.progressPercent,
    this.errorReason,
    this.verifyCountdownSeconds = 90,
    this.consecutive504Count = 0,
    this.localLockUntil,
    this.resultingVersion,
    this.isSubmittingWifi = false,
    this.isCheckingLiveVersion = false,
    this.liveVersionCheckTimedOut = false,
  });

  bool get isLocalLocked =>
      localLockUntil != null && localLockUntil!.isAfter(DateTime.now());

  FirmwareUpdateState copyWith({
    FirmwareUpdateStage? stage,
    FirmwareVersionSnapshot? snapshot,
    int? progressPercent,
    String? errorReason,
    int? verifyCountdownSeconds,
    int? consecutive504Count,
    DateTime? localLockUntil,
    String? resultingVersion,
    bool? isSubmittingWifi,
    bool? isCheckingLiveVersion,
    bool? liveVersionCheckTimedOut,
  }) {
    return FirmwareUpdateState(
      stage: stage ?? this.stage,
      snapshot: snapshot ?? this.snapshot,
      progressPercent: progressPercent ?? this.progressPercent,
      errorReason: errorReason,
      verifyCountdownSeconds: verifyCountdownSeconds ?? this.verifyCountdownSeconds,
      consecutive504Count: consecutive504Count ?? this.consecutive504Count,
      localLockUntil: localLockUntil ?? this.localLockUntil,
      resultingVersion: resultingVersion ?? this.resultingVersion,
      isSubmittingWifi: isSubmittingWifi ?? this.isSubmittingWifi,
      isCheckingLiveVersion: isCheckingLiveVersion ?? this.isCheckingLiveVersion,
      liveVersionCheckTimedOut: liveVersionCheckTimedOut ?? this.liveVersionCheckTimedOut,
    );
  }
}

class FirmwareUpdateController extends StateNotifier<FirmwareUpdateState> {
  FirmwareUpdateController(this.ref, this.controlUnitId, this.macAddress)
      : super(const FirmwareUpdateState()) {
    _init();
  }

  final Ref ref;
  final String controlUnitId;
  final String macAddress;

  StreamSubscription<OtaStatusEvent>? _statusSub;
  StreamSubscription<OtaVersionStatusEvent>? _versionSub;
  Timer? _verifyTimer;
  Timer? _versionCheckTimer;
  Timer? _resyncPoller;

  void _ensureResyncPoller() {
    if (_resyncPoller != null) return;
    _resyncPoller = Timer.periodic(kResyncPollInterval, (_) => _resyncFromBackend());
  }

  void _stopResyncPoller() {
    _resyncPoller?.cancel();
    _resyncPoller = null;
  }

  Future<void> _resyncFromBackend() async {
    if (!_kActiveStages.contains(state.stage)) {
      _stopResyncPoller();
      return;
    }
    try {
      final repo = ref.read(firmwareRepoProvider);
      final snapshot = await repo.getStatus(controlUnitId);
      final terminal = _terminalStageForBackendStatus(
          snapshot.backendStatus, snapshot.latestAttemptStatusCode);
      if (terminal != null) {
        _verifyTimer?.cancel();
        state = state.copyWith(
          snapshot: snapshot,
          stage: terminal,
          errorReason: (snapshot.latestAttemptReason?.isNotEmpty ?? false)
              ? snapshot.latestAttemptReason
              : state.errorReason,
        );
        _stopResyncPoller();
      }
    } catch (_) {
      // Transient poll failure — just try again next tick.
    }
  }

  void _init() {
    // Ensure the device's WebSocket is connected — equipment_details_screen
    // doesn't subscribe on its own (only the monitoring screen does), so the
    // Firmware Update Workspace must open its own subscription here.
    final telemetry = ref.read(telemetryServiceProvider);
    telemetry.subscribe(macAddress);

    _statusSub = telemetry.deviceOtaStatusStream(macAddress).listen(_onOtaStatus);
    _versionSub =
        telemetry.deviceOtaVersionStatusStream(macAddress).listen(_onVersionStatus);

    loadSnapshot();
  }

  Future<void> loadSnapshot() async {
    final repo = ref.read(firmwareRepoProvider);
    final snapshot = await repo.getStatus(controlUnitId);
    state = state.copyWith(
      snapshot: snapshot,
      stage: (snapshot.lockedForSeconds ?? 0) > 0
          ? FirmwareUpdateStage.locked
          : state.stage,
    );
  }

  Future<void> checkVersion() async {
    state = state.copyWith(isCheckingLiveVersion: true, liveVersionCheckTimedOut: false);
    _versionCheckTimer?.cancel();
    _versionCheckTimer = Timer(kLiveVersionCheckTimeout, () {
      // No reply within the window — most likely the device is powered off
      // or not connected to the MQTT broker. There's no MQTT-level NACK for
      // "nobody answered", so this local timeout is the only way to stop
      // spinning forever.
      state = state.copyWith(isCheckingLiveVersion: false, liveVersionCheckTimedOut: true);
    });

    try {
      final repo = ref.read(firmwareRepoProvider);
      await repo.requestCheckVersion(controlUnitId);
      // Reply (if any) arrives asynchronously via _onVersionStatus.
    } catch (_) {
      _versionCheckTimer?.cancel();
      state = state.copyWith(isCheckingLiveVersion: false, liveVersionCheckTimedOut: true);
    }
  }

  void _onVersionStatus(OtaVersionStatusEvent event) {
    _versionCheckTimer?.cancel();
    final current = state.snapshot;
    state = state.copyWith(
      snapshot: current?.copyWith(liveVersion: event.liveVersion),
      isCheckingLiveVersion: false,
      liveVersionCheckTimedOut: false,
    );
  }

  Future<void> startUpdate() async {
    final targetVersion = state.snapshot?.availableVersion;
    if (targetVersion == null) return;
    await _triggerOtaStart(targetVersion);
  }

  /// Publishes the actual /ota start command. Shared by [startUpdate] and
  /// [submitWifiCredentials] — the device only ever acts on a fresh /ota
  /// message; it does not retry on its own just from receiving new WiFi
  /// creds on /ota/wifi (confirmed: it responds promptly to /ota and
  /// /ota/version, but sits silent after /ota/wifi alone), so credentials
  /// alone would otherwise leave the screen waiting for a reply that never
  /// comes. [initialStage] lets the wifi-submit path jump straight to the
  /// same "downloading" step a fresh Update tap shows, instead of sitting
  /// on "Waiting to Connect" again.
  Future<void> _triggerOtaStart(
    String targetVersion, {
    FirmwareUpdateStage initialStage = FirmwareUpdateStage.waitingToConnect,
  }) async {
    if (state.isLocalLocked) return;

    state = state.copyWith(
      stage: initialStage,
      errorReason: null,
      progressPercent: initialStage == FirmwareUpdateStage.downloading ? 0 : null,
    );
    _ensureResyncPoller();

    try {
      final repo = ref.read(firmwareRepoProvider);
      await repo.startUpdate(controlUnitId, targetVersion: targetVersion);
    } on ApiException catch (e) {
      _stopResyncPoller();
      if (e.statusCode == 423) {
        state = state.copyWith(stage: FirmwareUpdateStage.locked);
      } else {
        state = state.copyWith(
          stage: FirmwareUpdateStage.criticalFailure,
          errorReason: 'Unable to update at this time. Please try after some time.',
        );
      }
    }
  }

  Future<void> submitWifiCredentials(String ssid, String password) async {
    state = state.copyWith(isSubmittingWifi: true);
    try {
      final repo = ref.read(firmwareRepoProvider);
      await repo.sendWifiCredentials(controlUnitId, ssid: ssid, password: password);
      state = state.copyWith(isSubmittingWifi: false);

      final targetVersion = state.snapshot?.availableVersion;
      if (targetVersion != null) {
        await _triggerOtaStart(targetVersion, initialStage: FirmwareUpdateStage.downloading);
      }
    } catch (_) {
      state = state.copyWith(isSubmittingWifi: false);
    }
  }

  /// Path B retry — re-show the Update button after a 504, unless the
  /// consecutive-failure streak has crossed the local UX threshold.
  void retryAfterConnectionLost() {
    if (state.isLocalLocked) {
      state = state.copyWith(stage: FirmwareUpdateStage.locked);
      return;
    }
    state = state.copyWith(stage: FirmwareUpdateStage.idle, errorReason: null);
  }

  void _onOtaStatus(OtaStatusEvent event) {
    switch (event.state) {
      case 'WIFI_CONNECTING':
        state = state.copyWith(stage: FirmwareUpdateStage.waitingToConnect);
        _ensureResyncPoller();
        break;

      case 'IN_PROGRESS':
        state = state.copyWith(
          stage: FirmwareUpdateStage.downloading,
          progressPercent: event.progressPercent ?? state.progressPercent,
        );
        _ensureResyncPoller();
        break;

      case 'DOWNLOAD_OK':
        _startVerifyCountdown();
        _ensureResyncPoller();
        break;

      case 'SUCCESS':
        _verifyTimer?.cancel();
        _stopResyncPoller();
        state = state.copyWith(
          stage: FirmwareUpdateStage.success,
          resultingVersion: event.resultingVersion,
          consecutive504Count: 0,
          localLockUntil: null,
        );
        // Refresh the DB-version snapshot so the device detail screen's
        // Firmware Version row reflects the new version immediately.
        loadSnapshot();
        break;

      case 'ROLLBACK':
        _verifyTimer?.cancel();
        _stopResyncPoller();
        state = state.copyWith(
          stage: FirmwareUpdateStage.rollback,
          errorReason: 'Unable to update. Please try again later.',
        );
        break;

      case 'FAILED':
        _onFailed(event);
        break;
    }
  }

  void _onFailed(OtaStatusEvent event) {
    _stopResyncPoller();
    switch (event.code) {
      case 401:
        state = state.copyWith(stage: FirmwareUpdateStage.wifiRequired);
        break;
      case 408:
        state = state.copyWith(
          stage: FirmwareUpdateStage.wifiTimeout,
          errorReason: 'Wi-Fi ID or Password is wrong. Please enter again.',
        );
        break;
      case 504:
        final streak = state.consecutive504Count + 1;
        DateTime? lockUntil = state.localLockUntil;
        if (streak > kMax504StreakBeforeLocalDisable) {
          lockUntil = DateTime.now().add(kLocalLockoutDuration);
        }
        state = state.copyWith(
          stage: lockUntil != null && lockUntil.isAfter(DateTime.now())
              ? FirmwareUpdateStage.locked
              : FirmwareUpdateStage.connectionLost,
          consecutive504Count: streak,
          localLockUntil: lockUntil,
          errorReason: 'Connection lost. Please make sure the device and Wi-Fi '
              'hotspot are turned on and placed close to each other.',
        );
        break;
      default:
        state = state.copyWith(
          stage: FirmwareUpdateStage.criticalFailure,
          consecutive504Count: 0,
          errorReason: 'Unable to update at this time. Please try after some time.',
        );
    }
  }

  void _startVerifyCountdown() {
    _verifyTimer?.cancel();
    state = state.copyWith(
      stage: FirmwareUpdateStage.verifying,
      verifyCountdownSeconds: 90,
    );
    _verifyTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = state.verifyCountdownSeconds - 1;
      if (remaining <= 0) {
        timer.cancel();
        state = state.copyWith(verifyCountdownSeconds: 0);
        return;
      }
      state = state.copyWith(verifyCountdownSeconds: remaining);
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _versionSub?.cancel();
    _verifyTimer?.cancel();
    _versionCheckTimer?.cancel();
    _resyncPoller?.cancel();
    super.dispose();
  }
}

final firmwareUpdateControllerProvider = StateNotifierProvider.family<
    FirmwareUpdateController, FirmwareUpdateState, ({String controlUnitId, String macAddress})>(
  (ref, args) => FirmwareUpdateController(ref, args.controlUnitId, args.macAddress),
);
