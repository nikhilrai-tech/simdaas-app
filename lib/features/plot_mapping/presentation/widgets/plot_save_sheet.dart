import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/features/plot_mapping/data/models/plot_model.dart';
import '../providers/plot_providers.dart';
import 'package:simdaas/core/services/auth_service.dart';

/// Shows the save-field bottom sheet and builds the resulting [PlotModel]
/// from what the user entered. Does NOT save it -- the caller (map_screen.dart)
/// does that via BackgroundSaveService so the map screen can show a
/// dismissible buffering banner instead of blocking on the network call.
/// Returns null if the sheet was cancelled.
Future<PlotModel?> showPlotSaveSheet(
    BuildContext context,
    WidgetRef ref,
    List<LatLng> normalizedPoints,
    double Function(List<LatLng>) computeAreaAcres,
    {PlotModel? existingPlot}) async {
  final nameCtrl = TextEditingController(text: existingPlot?.name);
  final zipCtrl = TextEditingController();
  final bedHeightCtrl = TextEditingController(text: existingPlot?.bedHeight?.toString());
  final areaCtrl = TextEditingController(text: existingPlot?.area?.toString());
  final rowSpacingCtrl = TextEditingController(text: existingPlot?.rowSpacing?.toString());
  final obstaclesCtrl = TextEditingController();
  final treeCountCtrl = TextEditingController(text: existingPlot?.treeCount?.toString());

  try {
    final suggested = computeAreaAcres(normalizedPoints);
    if (suggested > 0) areaCtrl.text = suggested.toStringAsFixed(2);
  } catch (_) {}

  final resMap = await showModalBottomSheet<Map<String, String>?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) => _PlotSaveSheetContent(
      ref: ref,
      existingPlot: existingPlot,
      nameCtrl: nameCtrl,
      zipCtrl: zipCtrl,
      bedHeightCtrl: bedHeightCtrl,
      areaCtrl: areaCtrl,
      rowSpacingCtrl: rowSpacingCtrl,
      obstaclesCtrl: obstaclesCtrl,
      treeCountCtrl: treeCountCtrl,
    ),
  );

  if (resMap == null) return null;

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

  return PlotModel(
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
      rowLines: existingPlot?.rowLines,
  );
}

// ---------------------------------------------------------------------------
// Extracted StatefulWidget — state (unit selections, errors) survives
// keyboard open/close rebuilds.
// ---------------------------------------------------------------------------

class _PlotSaveSheetContent extends StatefulWidget {
  final WidgetRef ref;
  final PlotModel? existingPlot;
  final TextEditingController nameCtrl;
  final TextEditingController zipCtrl;
  final TextEditingController bedHeightCtrl;
  final TextEditingController areaCtrl;
  final TextEditingController rowSpacingCtrl;
  final TextEditingController obstaclesCtrl;
  final TextEditingController treeCountCtrl;

  const _PlotSaveSheetContent({
    required this.ref,
    required this.existingPlot,
    required this.nameCtrl,
    required this.zipCtrl,
    required this.bedHeightCtrl,
    required this.areaCtrl,
    required this.rowSpacingCtrl,
    required this.obstaclesCtrl,
    required this.treeCountCtrl,
  });

  @override
  State<_PlotSaveSheetContent> createState() => _PlotSaveSheetContentState();
}

class _PlotSaveSheetContentState extends State<_PlotSaveSheetContent> {
  // Matches HECTARE_TO_ACRE in the backend (plot/migrations/0003_*).
  static const double _acreToHaFactor = 4046.8564224 / 10000.0;

  final _formKey = GlobalKey<FormState>();
  String _bedUnit = 'm';
  String _rowUnit = 'm';
  // Stored/sent value is genuinely acres (see PlotModel.area / user_area_acre),
  // so acre is the unit the field starts in.
  String _areaUnit = 'acre';
  String? _nameError;

  void _convertRow(String newUnit) {
    final currentVal = double.tryParse(widget.rowSpacingCtrl.text) ?? 0;
    if (currentVal == 0) { setState(() => _rowUnit = newUnit); return; }
    double inMeters;
    if (_rowUnit == 'in') inMeters = currentVal * 0.0254;
    else if (_rowUnit == 'ft') inMeters = currentVal * 0.3048;
    else inMeters = currentVal;
    double newVal;
    if (newUnit == 'in') newVal = inMeters / 0.0254;
    else if (newUnit == 'ft') newVal = inMeters / 0.3048;
    else newVal = inMeters;
    widget.rowSpacingCtrl.text = newVal.toStringAsFixed(2);
    setState(() => _rowUnit = newUnit);
  }

  void _convertBed(String newUnit) {
    final currentVal = double.tryParse(widget.bedHeightCtrl.text) ?? 0;
    if (currentVal == 0) { setState(() => _bedUnit = newUnit); return; }
    double inMeters;
    if (_bedUnit == 'in') inMeters = currentVal * 0.0254;
    else if (_bedUnit == 'ft') inMeters = currentVal * 0.3048;
    else inMeters = currentVal;
    double newVal;
    if (newUnit == 'in') newVal = inMeters / 0.0254;
    else if (newUnit == 'ft') newVal = inMeters / 0.3048;
    else newVal = inMeters;
    widget.bedHeightCtrl.text = newVal.toStringAsFixed(2);
    setState(() => _bedUnit = newUnit);
  }

  void _convertArea(String newUnit) {
    final currentVal = double.tryParse(widget.areaCtrl.text) ?? 0;
    if (currentVal == 0) { setState(() => _areaUnit = newUnit); return; }
    double inAcre;
    if (_areaUnit == 'ha') inAcre = currentVal / _acreToHaFactor;
    else inAcre = currentVal;
    double newVal;
    if (newUnit == 'ha') newVal = inAcre * _acreToHaFactor;
    else newVal = inAcre;
    widget.areaCtrl.text = newVal.toStringAsFixed(2);
    setState(() => _areaUnit = newUnit);
  }

  @override
  Widget build(BuildContext context) {
    // Read insets here — reactive to keyboard open/close
    final insets = MediaQuery.of(context).viewInsets.bottom;

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
        if (shouldExit && context.mounted) Navigator.of(context).pop();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                          controller: widget.nameCtrl,
                          decoration: InputDecoration(
                              labelText: 'Plot Name',
                              hintText: 'Plot Name',
                              errorText: _nameError),
                          onChanged: (_) {
                            if (_nameError != null) setState(() => _nameError = null);
                          },
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter plot name'
                              : null),
                      const SizedBox(height: 8),
                      TextFormField(
                          controller: widget.zipCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Pin / Zip Code',
                              hintText: 'Pin / Zip Code')),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                              controller: widget.bedHeightCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Bed Height',
                                  hintText: 'Bed Height'),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Enter bed height'
                                  : null),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 110,
                          child: DropdownButtonFormField<String>(
                            value: _bedUnit,
                            items: const [
                              DropdownMenuItem(value: 'm', child: Text('m')),
                              DropdownMenuItem(value: 'in', child: Text('in')),
                              DropdownMenuItem(value: 'ft', child: Text('ft')),
                            ],
                            onChanged: (v) => _convertBed(v ?? 'm'),
                            decoration: const InputDecoration(labelText: 'Unit'),
                          ),
                        )
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                              controller: widget.areaCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Approx Area',
                                  hintText: 'Approx Area'),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Enter approx area'
                                  : null),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 110,
                          child: DropdownButtonFormField<String>(
                            value: _areaUnit,
                            items: const [
                              DropdownMenuItem(value: 'ha', child: Text('ha')),
                              DropdownMenuItem(value: 'acre', child: Text('acre')),
                            ],
                            onChanged: (v) => _convertArea(v ?? 'ha'),
                            decoration: const InputDecoration(labelText: 'Unit'),
                          ),
                        )
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                              controller: widget.rowSpacingCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Row Spacing',
                                  hintText: 'Row Spacing'),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Enter row spacing'
                                  : null),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 110,
                          child: DropdownButtonFormField<String>(
                            value: _rowUnit,
                            items: const [
                              DropdownMenuItem(value: 'm', child: Text('m')),
                              DropdownMenuItem(value: 'in', child: Text('in')),
                              DropdownMenuItem(value: 'ft', child: Text('ft')),
                            ],
                            onChanged: (v) => _convertRow(v ?? 'm'),
                            decoration: const InputDecoration(labelText: 'Unit'),
                          ),
                        )
                      ]),
                      const SizedBox(height: 8),
                      TextFormField(
                          controller: widget.obstaclesCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Obstacles (notes)',
                              hintText: 'Obstacles (notes)')),
                      const SizedBox(height: 8),
                      TextFormField(
                          controller: widget.treeCountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Total Trees',
                              hintText: 'Total Trees')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;

                    final enteredName = widget.nameCtrl.text.trim().toLowerCase();
                    final owner = widget.ref.read(authServiceProvider).currentUserId ?? '';
                    try {
                      final existing = await widget.ref.read(plotRepoProvider).getPlots(owner);
                      final duplicate = existing.any((p) =>
                          p.name.trim().toLowerCase() == enteredName &&
                          p.id != widget.existingPlot?.id);
                      if (duplicate) {
                        setState(() => _nameError = 'A plot with this name already exists');
                        return;
                      }
                    } catch (_) {}

                    String bedOut = widget.bedHeightCtrl.text;
                    if (bedOut.isNotEmpty) {
                      final v = double.tryParse(bedOut);
                      if (v != null) {
                        if (_bedUnit == 'in') bedOut = (v * 0.0254).toString();
                        else if (_bedUnit == 'ft') bedOut = (v * 0.3048).toString();
                        else bedOut = v.toString();
                      }
                    }

                    String rowOut = widget.rowSpacingCtrl.text;
                    if (rowOut.isNotEmpty) {
                      final v = double.tryParse(rowOut);
                      if (v != null) {
                        if (_rowUnit == 'in') rowOut = (v * 0.0254).toString();
                        else if (_rowUnit == 'ft') rowOut = (v * 0.3048).toString();
                        else rowOut = v.toString();
                      }
                    }

                    // Always send genuine acres (user_area_acre), regardless
                    // of which unit is currently shown in the field.
                    String areaOut = widget.areaCtrl.text;
                    if (areaOut.isNotEmpty) {
                      final v = double.tryParse(areaOut);
                      if (v != null) {
                        if (_areaUnit == 'ha') areaOut = (v / _acreToHaFactor).toString();
                        else areaOut = v.toString();
                      }
                    }

                    final result = <String, String>{
                      'name': widget.nameCtrl.text,
                      'zip': widget.zipCtrl.text,
                      'bedHeight': bedOut,
                      'area': areaOut,
                      'rowSpacing': rowOut,
                      'obstacles': widget.obstaclesCtrl.text,
                      'treeCount': widget.treeCountCtrl.text,
                    };
                    Navigator.of(context).pop(result);
                  },
                  child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12.0),
                      child: Text('Save')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
