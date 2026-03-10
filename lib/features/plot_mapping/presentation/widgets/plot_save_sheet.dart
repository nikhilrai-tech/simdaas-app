import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/features/plot_mapping/data/models/plot_model.dart';
import 'package:simdaas/core/utils/error_utils.dart';
import '../providers/plot_providers.dart';
import 'package:simdaas/core/services/auth_service.dart';

/// Shows the save-field bottom sheet and performs save.
/// Returns true if saved successfully, false otherwise.
Future<bool> showPlotSaveSheet(
    BuildContext context,
    WidgetRef ref,
    List<LatLng> normalizedPoints,
    double Function(List<LatLng>) computeAreaHa,
    {PlotModel? existingPlot}) async {
  final nameCtrl = TextEditingController(text: existingPlot?.name);
  final zipCtrl = TextEditingController(); // Zip not in PlotModel? Let's keep empty for now or add if needed.
  final bedHeightCtrl = TextEditingController(text: existingPlot?.bedHeight?.toString());
  final areaCtrl = TextEditingController(text: existingPlot?.area?.toString());
  final rowSpacingCtrl = TextEditingController(text: existingPlot?.rowSpacing?.toString());
  final obstaclesCtrl = TextEditingController();
  final treeCountCtrl = TextEditingController(text: existingPlot?.treeCount?.toString());
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

      void convertRow(String newUnit) {
        final currentVal = double.tryParse(rowSpacingCtrl.text) ?? 0;
        if (currentVal == 0) {
          rowUnit = newUnit;
          return;
        }
        double inMeters;
        if (rowUnit == 'in') inMeters = currentVal * 0.0254;
        else if (rowUnit == 'ft') inMeters = currentVal * 0.3048;
        else inMeters = currentVal;

        double newVal;
        if (newUnit == 'in') newVal = inMeters / 0.0254;
        else if (newUnit == 'ft') newVal = inMeters / 0.3048;
        else newVal = inMeters;

        rowSpacingCtrl.text = newVal.toStringAsFixed(2);
        rowUnit = newUnit;
      }

      void convertBed(String newUnit) {
        final currentVal = double.tryParse(bedHeightCtrl.text) ?? 0;
        if (currentVal == 0) {
          bedUnit = newUnit;
          return;
        }
        double inMeters;
        if (bedUnit == 'in') inMeters = currentVal * 0.0254;
        else if (bedUnit == 'ft') inMeters = currentVal * 0.3048;
        else inMeters = currentVal;

        double newVal;
        if (newUnit == 'in') newVal = inMeters / 0.0254;
        else if (newUnit == 'ft') newVal = inMeters / 0.3048;
        else newVal = inMeters;

        bedHeightCtrl.text = newVal.toStringAsFixed(2);
        bedUnit = newUnit;
      }

      void convertArea(String newUnit) {
        final currentVal = double.tryParse(areaCtrl.text) ?? 0;
        if (currentVal == 0) {
          areaUnit = newUnit;
          return;
        }
        double inHa;
        if (areaUnit == 'acre') inHa = currentVal * 0.404686;
        else inHa = currentVal;

        double newVal;
        if (newUnit == 'acre') newVal = inHa / 0.404686;
        else newVal = inHa;

        areaCtrl.text = newVal.toStringAsFixed(2);
        areaUnit = newUnit;
      }
      return StatefulBuilder(builder: (ctx2, setState2) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final bool shouldExit = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Discard changes?'),
                    content: const Text(
                        'Are you sure you want to exit? Your progress will be lost.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Stay'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Discard', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ) ??
                false;

            if (shouldExit && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: AnimatedPadding(
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
                                    validator: (v) => (v == null || v.trim().isEmpty)
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
                                        const Text('Bed Height *'),
                                        const SizedBox(height: 6),
                                        TextFormField(
                                            controller: bedHeightCtrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(
                                                hintText: 'Bed Height'),
                                            validator: (v) => (v == null || v.trim().isEmpty)
                                                ? 'Enter bed height'
                                                : null),
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
                                          setState2(() => convertBed(v ?? 'm')),
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
                                        const Text('Approx Area *'),
                                        const SizedBox(height: 6),
                                        TextFormField(
                                            controller: areaCtrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(
                                                hintText: 'Approx Area'),
                                            validator: (v) => (v == null || v.trim().isEmpty)
                                                ? 'Enter approx area'
                                                : null),
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
                                          setState2(() => convertArea(v ?? 'ha')),
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
                                        const Text('Row Spacing *'),
                                        const SizedBox(height: 6),
                                        TextFormField(
                                            controller: rowSpacingCtrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(
                                                hintText: 'Row Spacing'),
                                            validator: (v) => (v == null || v.trim().isEmpty)
                                                ? 'Enter row spacing'
                                                : null),
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
                                          setState2(() => convertRow(v ?? 'm')),
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
                              // Convert current values back to base units (m/ha) for result
                              String bedOut = bedHeightCtrl.text;
                              if (bedOut.isNotEmpty) {
                                final v = double.tryParse(bedOut);
                                if (v != null) {
                                  if (bedUnit == 'in') bedOut = (v * 0.0254).toString();
                                  else if (bedUnit == 'ft') bedOut = (v * 0.3048).toString();
                                  else bedOut = v.toString();
                                }
                              }

                              String rowOut = rowSpacingCtrl.text;
                              if (rowOut.isNotEmpty) {
                                final v = double.tryParse(rowOut);
                                if (v != null) {
                                  if (rowUnit == 'in') rowOut = (v * 0.0254).toString();
                                  else if (rowUnit == 'ft') rowOut = (v * 0.3048).toString();
                                  else rowOut = v.toString();
                                }
                              }

                              String areaOut = areaCtrl.text;
                              if (areaOut.isNotEmpty) {
                                final v = double.tryParse(areaOut);
                                if (v != null) {
                                  if (areaUnit == 'acre') areaOut = (v * 0.404686).toString();
                                  else areaOut = v.toString();
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
          ),
        );
      });
    },
  );

  if (resMap == null) return false;
  
  final owner = ref.read(authServiceProvider).currentUserId;
  double? approx;
  try {
    final v = resMap['area'] ?? '';
    approx = v.isEmpty ? null : double.tryParse(v);
  } catch (_) {
    approx = null;
  }
  double? rowSpacing;
  try {
    final v = resMap['rowSpacing'] ?? '';
    rowSpacing = v.isEmpty ? null : double.tryParse(v);
  } catch (_) {
    rowSpacing = null;
  }
  int? treeCount;
  try {
    final v = resMap['treeCount'] ?? '';
    treeCount = v.isEmpty ? null : int.tryParse(v);
  } catch (_) {
    treeCount = null;
  }

  final model = PlotModel(
      id: existingPlot?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: resMap['name'] ?? '',
      bedHeight: (resMap['bedHeight'] ?? '').isEmpty
          ? null
          : double.tryParse(resMap['bedHeight'] ?? ''),
      area: approx,
      rowSpacing: rowSpacing,
      treeCount: treeCount,
      polygon: normalizedPoints,
      userId: owner,
  );

  final repo = ref.read(plotRepoProvider);
  try {
    if (existingPlot != null) {
      await repo.updatePlot(model);
    } else {
      await repo.addPlot(model);
    }
  } catch (e) {
    if (context.mounted) {
      showPolishedError(context, e, fallback: 'Error saving plot');
    }
    return false;
  }

  final currentUserId =
      ref.read(authServiceProvider).currentUserId ?? 'demo_user';
  ref.invalidate(plotsListProvider(currentUserId));
  return true;
}
