import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/users_providers.dart'
    as users_provs;
import 'package:simdaas/core/widgets/api_error_widget.dart';

/// Shows a dialog to select an operator. Returns the selected operator id
/// or null if cancelled. Caller is responsible for applying the selection
/// to any state provider.
Future<String?> showSelectOperatorDialog(BuildContext parentCtx, WidgetRef ref,
    {String? initialSelected}) async {
  String? tempSelected = initialSelected;

  final picked = await showDialog<String?>(
    context: parentCtx,
    builder: (ctx) {
      return Consumer(builder: (c, ref2, _) {
        final opsAsync = ref2.watch(users_provs.operatorsListProvider);
        return opsAsync.when(
          data: (docs) {
            return StatefulBuilder(builder: (ctx2, setStateDialog) {
              final options = docs
                  .map((d) {
                    final doc = Map<String, dynamic>.from(d as Map);
                    final idStr = (doc['id'] ?? doc['pk'])?.toString() ?? '';
                    final name =
                        (doc['name'] as String?) ?? doc['email'] ?? idStr;
                    final phone = (doc['phone'] as String?) ?? '';
                    return ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(name),
                      subtitle: Text(phone),
                      onTap: () => setStateDialog(() => tempSelected = idStr),
                      selected: tempSelected == idStr,
                    );
                  })
                  .where((w) => w.title != null)
                  .toList();

              return AlertDialog(
                title: const Text('Select Operator'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: options.isEmpty
                      ? const Text('No operators found')
                      : ListView(children: options),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        final newId =
                            await showAddOperatorDialog(parentCtx, ref);
                        if (newId != null) Navigator.of(parentCtx).pop(newId);
                      },
                      child: const Text('Add New Operator')),
                  ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(tempSelected),
                      child: const Text('OK')),
                ],
              );
            });
          },
          loading: () => const AlertDialog(
              title: Text('Select Operator'),
              content: SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()))),
          error: (e, st) => AlertDialog(
              title: const Text('Select Operator'),
              content: SizedBox(
                  width: double.maxFinite, child: ApiErrorWidget(error: e)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(null),
                    child: const Text('OK'))
              ]),
        );
      });
    },
  );

  return picked;
}

/// Shows the add-operator dialog and returns the created operator id (or null).
Future<String?> showAddOperatorDialog(
    BuildContext parentCtx, WidgetRef ref) async {
  final formKeyOp = GlobalKey<FormState>();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final experienceCtrl = TextEditingController();
  final assignedMachineCtrl = TextEditingController();
  final shiftTimingCtrl = TextEditingController();
  bool isActive = true;

  final result = await showDialog<String?>(
    context: parentCtx,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx2, setStateDialog) {
        final creatingNotifier = ValueNotifier<bool>(false);
        return AlertDialog(
          title: const Text('Add New Operator'),
          content: SingleChildScrollView(
            child: Form(
              key: formKeyOp,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter name' : null),
                TextFormField(
                    controller: phoneCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Contact number'),
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                      if (digits.length < 7 || digits.length > 20)
                        return 'Invalid phone number';
                      return null;
                    }),
                TextFormField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      final t = v.trim();
                      final emailRx = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");
                      if (!emailRx.hasMatch(t)) return 'Invalid email';
                      return null;
                    }),
                TextFormField(
                    controller: addressCtrl,
                    decoration: const InputDecoration(labelText: 'Address')),
                TextFormField(
                    controller: experienceCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Experience (years)'),
                    keyboardType: TextInputType.number),
                TextFormField(
                    controller: assignedMachineCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Assigned machine')),
                TextFormField(
                    controller: shiftTimingCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Shift timing')),
                Row(children: [
                  const Text('Active'),
                  const Spacer(),
                  Switch(
                      value: isActive,
                      onChanged: (v) => setStateDialog(() => isActive = v))
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel')),
            ValueListenableBuilder<bool>(
                valueListenable: creatingNotifier,
                builder: (context, creatingValue, _) {
                  return creatingValue
                      ? const Padding(
                          padding: EdgeInsets.only(right: 8.0),
                          child: SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : const SizedBox.shrink();
                }),
            ElevatedButton(
                onPressed: () async {
                  if (creatingNotifier.value) return;
                  if (formKeyOp.currentState == null ||
                      !formKeyOp.currentState!.validate()) return;
                  creatingNotifier.value = true;
                  try {
                    final opId = await ref
                        .read(users_provs.operatorsControllerProvider)
                        .createOperator(
                          name: nameCtrl.text.trim(),
                          contactNumber: phoneCtrl.text.trim(),
                          email: emailCtrl.text.trim(),
                          address: addressCtrl.text.trim(),
                          experienceYears:
                              int.tryParse(experienceCtrl.text.trim()),
                          assignedMachine: assignedMachineCtrl.text.trim(),
                          shiftTiming: shiftTimingCtrl.text.trim(),
                          isActive: isActive,
                        );
                    ref.invalidate(users_provs.operatorsListProvider);
                    if (ctx.mounted)
                      ScaffoldMessenger.of(parentCtx).showSnackBar(
                          const SnackBar(content: Text('Created operator')));
                    Navigator.of(ctx).pop(opId);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(parentCtx)
                          .showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                    creatingNotifier.value = false;
                  }
                },
                child: const Text('Create')),
          ],
        );
      });
    },
  );

  return result;
}
