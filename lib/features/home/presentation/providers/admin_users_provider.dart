import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/auth_service.dart';

/// One row from GET /api/admin/users/ — Super Admin only.
class AdminUserEntity {
  final int id;
  final String username;
  final String email;
  final String name;
  final String type; // 'S' | 'C' | 'Ct'
  final String companytype;
  final String? contact;
  final bool isActive;
  final bool emailConfirmed;
  final bool isAdmin;
  final bool isSuperadmin;
  final DateTime? dateJoined;
  final DateTime? lastLogin;

  const AdminUserEntity({
    required this.id,
    required this.username,
    required this.email,
    required this.name,
    required this.type,
    required this.companytype,
    this.contact,
    required this.isActive,
    required this.emailConfirmed,
    required this.isAdmin,
    required this.isSuperadmin,
    this.dateJoined,
    this.lastLogin,
  });

  String get typeLabel {
    switch (type) {
      case 'S':
        return 'Super Admin';
      case 'Ct':
        return 'Company Staff';
      default:
        return 'Company';
    }
  }

  factory AdminUserEntity.fromJson(Map<String, dynamic> json) {
    return AdminUserEntity(
      id: json['id'] as int,
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'C',
      companytype: json['companytype'] as String? ?? '',
      contact: json['contact'] as String?,
      isActive: json['is_active'] as bool? ?? false,
      emailConfirmed: json['email_confirmed'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool? ?? false,
      isSuperadmin: json['is_superadmin'] as bool? ?? false,
      dateJoined: DateTime.tryParse(json['date_joined']?.toString() ?? ''),
      lastLogin: DateTime.tryParse(json['last_login']?.toString() ?? ''),
    );
  }
}

/// Backs the Admin Dashboard's "All Users" screen.
final adminUsersProvider = FutureProvider<List<AdminUserEntity>>((ref) async {
  final api = ref.read(apiServiceProvider);
  final json = await api.getJson('/api/admin/users/') as List<dynamic>;
  return json
      .map((e) => AdminUserEntity.fromJson(e as Map<String, dynamic>))
      .toList();
});
