import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/users_providers.dart';
import 'package:simdaas/core/widgets/api_error_widget.dart';

class OperatorListScreen extends ConsumerWidget {
  final bool showFab;
  const OperatorListScreen({super.key, this.showFab = true});

  Future<void> _showAddOperatorDialog(
      BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final experienceController = TextEditingController();
    final assignedMachineController = TextEditingController();
    final shiftTimingController = TextEditingController();
    bool isActive = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Operator'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              TextField(
                controller: experienceController,
                decoration:
                    const InputDecoration(labelText: 'Experience years'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: assignedMachineController,
                decoration:
                    const InputDecoration(labelText: 'Assigned machine'),
              ),
              TextField(
                controller: shiftTimingController,
                decoration: const InputDecoration(labelText: 'Shift timing'),
              ),
              Row(
                children: [
                  const Text('Active'),
                  const Spacer(),
                  StatefulBuilder(builder: (ctx, setState) {
                    return Switch(
                      value: isActive,
                      onChanged: (v) => setState(() => isActive = v),
                    );
                  })
                ],
              )
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final phone = phoneController.text.trim();
              final email = emailController.text.trim();
              final emailRegex = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");
              final phoneDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
              if (email.isNotEmpty && !emailRegex.hasMatch(email)) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid email')));
                return;
              }
              if (phone.isNotEmpty &&
                  (phoneDigits.length < 7 || phoneDigits.length > 20)) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid phone number')));
                return;
              }
              final address = addressController.text.trim();
              final experience =
                  int.tryParse(experienceController.text.trim());
              final assigned = assignedMachineController.text.trim();
              final shift = shiftTimingController.text.trim();
              await ref.read(operatorsControllerProvider).createOperator(
                    name: name,
                    contactNumber: phone,
                    email: email,
                    address: address,
                    experienceYears: experience,
                    assignedMachine: assigned,
                    shiftTiming: shift,
                    isActive: isActive,
                  );
              Navigator.of(context).pop(true);
            },
            child: const Text('Add'),
          )
        ],
      ),
    );

    if (result == true) {
      // refresh list
      ref.invalidate(operatorsListProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opsAsync = ref.watch(operatorsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Operators')),
      body: opsAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No operators yet'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, idx) {
              final op = list[idx];
              return ListTile(
                title: Text(op['name'] ?? 'Unnamed'),
                subtitle: Text(op['phone'] ?? ''),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ApiErrorWidget(
            error: e, onRetry: () => ref.invalidate(operatorsListProvider)),
      ),
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: () => _showAddOperatorDialog(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
