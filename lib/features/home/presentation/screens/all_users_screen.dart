import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/admin_users_provider.dart';

/// Super Admin-only directory of every registered user — GET /api/admin/users/.
class AllUsersScreen extends ConsumerWidget {
  const AllUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('All Users')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminUsersProvider),
        child: usersAsync.when(
          data: (users) {
            if (users.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No users found.')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _UserTile(user: users[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load users: $e')),
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});
  final AdminUserEntity user;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: user.isSuperadmin
              ? Colors.deepPurple
              : Theme.of(context).colorScheme.primary,
          child: Text(
            (user.name.isNotEmpty ? user.name : user.username)
                .substring(0, 1)
                .toUpperCase(),
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(user.name.isNotEmpty ? user.name : user.username),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email),
            Text('${user.typeLabel} • @${user.username}'),
            if (user.contact != null && user.contact!.isNotEmpty)
              Text('Contact: ${user.contact}'),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Chip(
              label: Text(
                user.isActive ? 'Active' : 'Inactive',
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
              backgroundColor: user.isActive ? Colors.green : Colors.grey,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            if (!user.emailConfirmed)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Unverified', style: TextStyle(fontSize: 11, color: Colors.orange)),
              ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
