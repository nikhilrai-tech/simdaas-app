import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// App version + build number, read from the platform package info (backed
/// by pubspec.yaml's `version:` field at build time).
final appPackageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});
