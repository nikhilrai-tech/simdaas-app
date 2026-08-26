import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/providers/users_providers.dart';
import '../features/home/presentation/providers/admin_users_provider.dart';
import '../features/job_planner/presentation/providers/job_providers.dart';
import '../features/firmware_update/presentation/providers/firmware_update_providers.dart';
import '../features/plot_mapping/presentation/providers/plot_providers.dart';
import '../features/reports/presentation/providers/report_providers.dart';
import '../features/reports/presentation/providers/session_providers.dart';

/// Clears every cached provider that holds data fetched for the previously
/// signed-in user.
///
/// Most list/detail providers in this app are plain (non-family)
/// `FutureProvider`s, so Riverpod caches their result forever until
/// something invalidates them — signing out clears the auth token but never
/// touched this cache, so logging in as a different user (without fully
/// restarting the app) kept showing the previous user's reports, sessions,
/// jobs, etc. Providers that are already keyed by userId (equipment,
/// tractors/sprayers/control units) don't need this — a different userId
/// naturally gets a fresh cache entry.
///
/// Call this right after `AuthService.signOut()` completes, before
/// navigating back to the login screen.
void clearUserScopedCaches(WidgetRef ref) {
  ref.invalidate(reportsListProvider);
  ref.invalidate(reportDetailProvider);
  ref.invalidate(activeSessionsListProvider);
  ref.invalidate(jobsListProvider);
  ref.invalidate(plotsListProvider);
  ref.invalidate(plotByIdProvider);
  ref.invalidate(usersListProvider);
  ref.invalidate(operatorsListProvider);
  ref.invalidate(adminUsersProvider);
  ref.invalidate(firmwareAlertsProvider);
}
