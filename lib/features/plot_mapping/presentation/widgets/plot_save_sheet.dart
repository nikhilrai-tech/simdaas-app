import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/features/plot_mapping/data/models/plot_model.dart';
import '../providers/plot_providers.dart';
import 'package:simdaas/core/services/auth_service.dart';

/// Shows the save-field bottom sheet and performs save.
/// Returns true if saved successfully, false otherwise.
Future<bool> showPlotSaveSheet(
    BuildContext context,
    WidgetRef ref,
    List<LatLng> normalizedPoints,
    double Function(List<LatLng>) computeAreaHa) async {
  final nameCtrl = TextEditingController();
  final zipCtrl = TextEditingController();
  final bedHeightCtrl = TextEditingController();
  final areaCtrl = TextEditingController();
  final rowSpacingCtrl = TextEditingController();
  final obstaclesCtrl = TextEditingController();
  final treeCountCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  try {
    final suggested = computeAreaHa(normalizedPoints);
    if (suggested > 0) areaCtrl.text = suggested.toStringAsFixed(2);
  } catch (_) {}

  final resMap = await showModalBottomSheet<Map<String, String>?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) {
      final insets = MediaQuery.of(ctx).viewInsets.bottom;
      final maxHeight = MediaQuery.of(ctx).size.height * 0.9;
      // Local unit state for bed, row spacing and area. Use StatefulBuilder to
      // update unit selectors within the modal. Area defaults to hectares.
      String bedUnit = 'm';
      String rowUnit = 'm';
      String areaUnit = 'ha';
      return StatefulBuilder(builder: (ctx2, setState2) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: insets),
          child: FractionallySizedBox(
            heightFactor: 0.75,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                elevation: 8,
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(12))),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 12.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                                color: Colors.grey[400],
                                borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Form(
                          key: formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Plot Name'),
                              const SizedBox(height: 6),
                              TextFormField(
                                  controller: nameCtrl,
                                  decoration: const InputDecoration(
                                      hintText: 'Plot Name'),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Enter plot name'
                                      : null),
                              const SizedBox(height: 8),
                              const Text('Pin / Zip Code'),
                              const SizedBox(height: 6),
                              TextFormField(
                                  controller: zipCtrl,
                                  decoration: const InputDecoration(
                                      hintText: 'Pin / Zip Code')),
                              const SizedBox(height: 8),
                              Row(children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text('Bed Height'),
                                      const SizedBox(height: 6),
                                      TextFormField(
                                          controller: bedHeightCtrl,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(
                                              hintText: 'Bed Height')),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 110,
                                  child: DropdownButtonFormField<String>(
                                    value: bedUnit,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'm', child: Text('m')),
                                      DropdownMenuItem(
                                          value: 'in', child: Text('in')),
                                      DropdownMenuItem(
                                          value: 'ft', child: Text('ft')),
                                    ],
                                    onChanged: (v) =>
                                        setState2(() => bedUnit = v ?? 'm'),
                                    decoration: const InputDecoration(
                                        labelText: 'Unit'),
                                  ),
                                )
                              ]),
                              const SizedBox(height: 8),
                              Row(children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text('Approx Area'),
                                      const SizedBox(height: 6),
                                      TextFormField(
                                          controller: areaCtrl,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(
                                              hintText: 'Approx Area')),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 110,
                                  child: DropdownButtonFormField<String>(
                                    value: areaUnit,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'ha', child: Text('ha')),
                                      DropdownMenuItem(
                                          value: 'acre', child: Text('acre')),
                                    ],
                                    onChanged: (v) =>
                                        setState2(() => areaUnit = v ?? 'ha'),
                                    decoration: const InputDecoration(
                                        labelText: 'Unit'),
                                  ),
                                )
                              ]),
                              const SizedBox(height: 8),
                              Row(children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text('Row Spacing'),
                                      const SizedBox(height: 6),
                                      TextFormField(
                                          controller: rowSpacingCtrl,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(
                                              hintText: 'Row Spacing')),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 110,
                                  child: DropdownButtonFormField<String>(
                                    value: rowUnit,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'm', child: Text('m')),
                                      DropdownMenuItem(
                                          value: 'in', child: Text('in')),
                                      DropdownMenuItem(
                                          value: 'ft', child: Text('ft')),
                                    ],
                                    onChanged: (v) =>
                                        setState2(() => rowUnit = v ?? 'm'),
                                    decoration: const InputDecoration(
                                        labelText: 'Unit'),
                                  ),
                                )
                              ]),
                              const SizedBox(height: 8),
                              const Text('Obstacles (notes)'),
                              const SizedBox(height: 6),
                              TextFormField(
                                  controller: obstaclesCtrl,
                                  decoration: const InputDecoration(
                                      hintText: 'Obstacles (notes)')),
                              const SizedBox(height: 8),
                              const Text('Total Trees'),
                              const SizedBox(height: 6),
                              TextFormField(
                                  controller: treeCountCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      hintText: 'Total Trees')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            if (!formKey.currentState!.validate()) return;
                            // Convert bedHeight and rowSpacing to meters based on selected unit
                            String bedOut = bedHeightCtrl.text;
                            if (bedOut.isNotEmpty) {
                              final v = double.tryParse(bedOut);
                              if (v != null) {
                                if (bedUnit == 'in')
                                  bedOut = (v * 0.0254).toString();
                                else if (bedUnit == 'ft')
                                  bedOut = (v * 0.3048).toString();
                                else
                                  bedOut = v.toString();
                              }
                            }

                            String rowOut = rowSpacingCtrl.text;
                            if (rowOut.isNotEmpty) {
                              final v = double.tryParse(rowOut);
                              if (v != null) {
                                if (rowUnit == 'in')
                                  rowOut = (v * 0.0254).toString();
                                else if (rowUnit == 'ft')
                                  rowOut = (v * 0.3048).toString();
                                else
                                  rowOut = v.toString();
                              }
                            }

                            // Convert area to hectares if necessary. AreaCtrl is prefilled
                            // in hectares by computeAreaHa, and default unit is 'ha'. If
                            // user selects 'acre', convert acres -> hectares.
                            String areaOut = areaCtrl.text;
                            if (areaOut.isNotEmpty) {
                              final v = double.tryParse(areaOut);
                              if (v != null) {
                                if (areaUnit == 'acre') {
                                  // 1 acre = 0.404686 hectares
                                  areaOut = (v * 0.404686).toString();
                                } else {
                                  areaOut = v.toString();
                                }
                              }
                            }

                            final result = <String, String>{
                              'name': nameCtrl.text,
                              'zip': zipCtrl.text,
                              'bedHeight': bedOut,
                              'area': areaOut,
                              'rowSpacing': rowOut,
                              'obstacles': obstaclesCtrl.text,
                              'treeCount': treeCountCtrl.text,
                            };
                            Navigator.of(ctx).pop(result);
                          },
                          child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12.0),
                              child: Text('Save')),
                        ),
                        SizedBox(height: insets),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      });
    },
  );

  if (resMap == null) return false;

  final owner = ref.read(authServiceProvider).currentUserId;
  double? approx;
  try {
    approx = double.parse((resMap['area'] ?? '').toString());
  } catch (_) {
    approx = null;
  }
  double? rowSpacing;
  try {
    rowSpacing = double.parse((resMap['rowSpacing'] ?? '').toString());
  } catch (_) {
    rowSpacing = null;
  }
  int? treeCount;
  try {
    treeCount = int.parse(resMap['treeCount'] ?? '');
  } catch (_) {
    treeCount = null;
  }

  final model = PlotModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: resMap['name'] ?? '',
      bedHeight: (resMap['bedHeight'] ?? '').isEmpty
          ? null
          : double.tryParse(resMap['bedHeight'] ?? ''),
      area: approx,
      rowSpacing: rowSpacing,
      treeCount: treeCount,
      polygon: normalizedPoints,
      userId: owner);

  final repo = ref.read(plotRepoProvider);
  await repo.addPlot(model);

  final currentUserId =
      ref.read(authServiceProvider).currentUserId ?? 'demo_user';
  ref.invalidate(plotsListProvider(currentUserId));
  return true;
}
