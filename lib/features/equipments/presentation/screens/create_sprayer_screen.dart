import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/equipment_providers.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'dart:convert';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/utils/api_error.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';

// Helper to keep PageView pages alive so their FormState remains mounted
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class CreateSprayerScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existingData;
  const CreateSprayerScreen({super.key, this.existingData});

  @override
  ConsumerState<CreateSprayerScreen> createState() =>
      _CreateSprayerScreenState();
}

class _CreateSprayerScreenState extends ConsumerState<CreateSprayerScreen> {
  bool _debugShown = false;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _wheelDiameter = TextEditingController();
  final _screwsInWheel = TextEditingController();
  final _hingeToAxle = TextEditingController();
  final _hingeToNozzle = TextEditingController();
  final _hingeToControlUnit = TextEditingController();
  final _axleLength = TextEditingController();
  final _nozzleCount = TextEditingController();
  final _tankCapacity = TextEditingController();
  late final List<GlobalKey<FormState>> _pageKeys;
  final _pageController = PageController();
  int _currentPage = 0;
  bool _isSaving = false;
  // Unit selectors for meter fields
  String _wheelDiameterUnit = 'm';
  String _hingeToAxleUnit = 'm';
  String _hingeToNozzleUnit = 'm';
  String _hingeToControlUnitUnit = 'm';
  String _axleLengthUnit = 'm';

  @override
  void dispose() {
    _name.dispose();
    _wheelDiameter.dispose();
    _screwsInWheel.dispose();
    _hingeToAxle.dispose();
    _hingeToNozzle.dispose();
    _hingeToControlUnit.dispose();
    _axleLength.dispose();
    _nozzleCount.dispose();
    _tankCapacity.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _pageKeys = List.generate(9, (_) => GlobalKey<FormState>());
    if (widget.existingData != null) {
      final ex = widget.existingData!;
      // Prefill controllers once in initState so user edits aren't overwritten on rebuild
      _name.text = ex['name'] as String? ?? '';
      if (ex['wheelDiameter'] != null)
        _wheelDiameter.text = '${ex['wheelDiameter']}';
      if (ex['screwsInWheel'] != null)
        _screwsInWheel.text = '${ex['screwsInWheel']}';
      if (ex['hingeToAxle'] != null) _hingeToAxle.text = '${ex['hingeToAxle']}';
      if (ex['hingeToNozzle'] != null)
        _hingeToNozzle.text = '${ex['hingeToNozzle']}';
      if (ex['hingeToControlUnit'] != null)
        _hingeToControlUnit.text = '${ex['hingeToControlUnit']}';
      if (ex['axleLength'] != null) _axleLength.text = '${ex['axleLength']}';
      if (ex['nozzleCount'] != null) _nozzleCount.text = '${ex['nozzleCount']}';
      if (ex['tankCapacity'] != null)
        _tankCapacity.text = '${ex['tankCapacity']}';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_debugShown && mounted) {
          debugPrint(
              'CreateSprayerScreen existingData: ${widget.existingData}');
          _debugShown = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingData != null;

    return Scaffold(
        appBar: AppBar(title: Text(isEditing ? 'Edit Sprayer' : 'Add Sprayer')),
        body: SafeArea(
          child: Stack(children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 8.0),
                  child: LinearProgressIndicator(
                    value: (1.0 * (_currentPage + 1)) / 9,
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    children: [
                      _KeepAlive(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Form(
                            key: _pageKeys[0],
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 200,
                                  child: Image.asset(
                                    'assets/sprayer/sprayer_name.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, st) =>
                                        const Center(
                                      child: Icon(Icons.image_not_supported,
                                          size: 48),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _name,
                                  decoration: const InputDecoration(
                                      labelText: 'Sprayer name'),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Enter name'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _KeepAlive(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Form(
                            key: _pageKeys[1],
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 200,
                                  child: Image.asset(
                                    'assets/sprayer/wheel_diameter_sprayer.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, st) =>
                                        const Center(
                                      child: Icon(Icons.image_not_supported,
                                          size: 48),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _wheelDiameter,
                                      decoration: const InputDecoration(
                                          labelText: 'Wheel diameter'),
                                      keyboardType: TextInputType.numberWithOptions(
                                          decimal: true),
                                      validator: (v) => (v == null || v.isEmpty)
                                          ? 'Enter wheel diameter'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 110,
                                    child: DropdownButtonFormField<String>(
                                      value: _wheelDiameterUnit,
                                      items: const [
                                        DropdownMenuItem(value: 'm', child: Text('m')),
                                        DropdownMenuItem(value: 'in', child: Text('in')),
                                        DropdownMenuItem(value: 'ft', child: Text('ft')),
                                      ],
                                      onChanged: (v) => setState(() => _wheelDiameterUnit = v ?? 'm'),
                                      decoration: const InputDecoration(labelText: 'Unit'),
                                    ),
                                  )
                                ]),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _KeepAlive(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Form(
                            key: _pageKeys[2],
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 200,
                                  child: Image.asset(
                                    'assets/sprayer/screws_in_wheel_sprayer.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, st) =>
                                        const Center(
                                      child: Icon(Icons.image_not_supported,
                                          size: 48),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _screwsInWheel,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'Number of screws/nuts in wheel'),
                                  keyboardType: TextInputType.number,
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Enter number of screws/nuts'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _KeepAlive(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Form(
                            key: _pageKeys[3],
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 200,
                                  child: Image.asset(
                                    'assets/sprayer/axle_length_sprayer.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, st) =>
                                        const Center(
                                      child: Icon(Icons.image_not_supported,
                                          size: 48),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _axleLength,
                                      decoration: const InputDecoration(
                                          labelText: 'Axle length'),
                                      keyboardType: TextInputType.numberWithOptions(
                                          decimal: true),
                                      validator: (v) => (v == null || v.isEmpty)
                                          ? 'Enter axle length'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 110,
                                    child: DropdownButtonFormField<String>(
                                      value: _axleLengthUnit,
                                      items: const [
                                        DropdownMenuItem(value: 'm', child: Text('m')),
                                        DropdownMenuItem(value: 'in', child: Text('in')),
                                        DropdownMenuItem(value: 'ft', child: Text('ft')),
                                      ],
                                      onChanged: (v) => setState(() => _axleLengthUnit = v ?? 'm'),
                                      decoration: const InputDecoration(labelText: 'Unit'),
                                    ),
                                  )
                                ]),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _KeepAlive(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Form(
                            key: _pageKeys[4],
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 200,
                                  child: Image.asset(
                                    'assets/sprayer/nozzle_count_sprayer.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, st) =>
                                        const Center(
                                      child: Icon(Icons.image_not_supported,
                                          size: 48),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _nozzleCount,
                                  decoration: const InputDecoration(
                                      labelText: 'Number of nozzles'),
                                  keyboardType: TextInputType.number,
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Enter nozzle count'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _KeepAlive(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Form(
                            key: _pageKeys[5],
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 200,
                                  child: Image.asset(
                                    'assets/sprayer/tank_capacity_sprayer.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, st) =>
                                        const Center(
                                      child: Icon(Icons.image_not_supported,
                                          size: 48),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _tankCapacity,
                                  decoration: const InputDecoration(
                                      labelText: 'Tank capacity (L)'),
                                  keyboardType: TextInputType.numberWithOptions(
                                      decimal: true),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Enter tank capacity'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _KeepAlive(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Form(
                            key: _pageKeys[6],
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 200,
                                  child: Image.asset(
                                    'assets/sprayer/hinge_to_axle_sprayer.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, st) =>
                                        const Center(
                                      child: Icon(Icons.image_not_supported,
                                          size: 48),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _hingeToAxle,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Distance between hinge point and axle'),
                                      keyboardType: TextInputType.numberWithOptions(
                                          decimal: true),
                                      validator: (v) => (v == null || v.isEmpty)
                                          ? 'Enter hinge->axle distance'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 110,
                                    child: DropdownButtonFormField<String>(
                                      value: _hingeToAxleUnit,
                                      items: const [
                                        DropdownMenuItem(value: 'm', child: Text('m')),
                                        DropdownMenuItem(value: 'in', child: Text('in')),
                                        DropdownMenuItem(value: 'ft', child: Text('ft')),
                                      ],
                                      onChanged: (v) => setState(() => _hingeToAxleUnit = v ?? 'm'),
                                      decoration: const InputDecoration(labelText: 'Unit'),
                                    ),
                                  )
                                ]),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _KeepAlive(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Form(
                            key: _pageKeys[7],
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 200,
                                  child: Image.asset(
                                    'assets/sprayer/hinge_to_nozzle_sprayer.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, st) =>
                                        const Center(
                                      child: Icon(Icons.image_not_supported,
                                          size: 48),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _hingeToNozzle,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Distance between hinge point and nozzle'),
                                      keyboardType: TextInputType.numberWithOptions(
                                          decimal: true),
                                      validator: (v) => (v == null || v.isEmpty)
                                          ? 'Enter hinge->nozzle distance'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 110,
                                    child: DropdownButtonFormField<String>(
                                      value: _hingeToNozzleUnit,
                                      items: const [
                                        DropdownMenuItem(value: 'm', child: Text('m')),
                                        DropdownMenuItem(value: 'in', child: Text('in')),
                                        DropdownMenuItem(value: 'ft', child: Text('ft')),
                                      ],
                                      onChanged: (v) => setState(() => _hingeToNozzleUnit = v ?? 'm'),
                                      decoration: const InputDecoration(labelText: 'Unit'),
                                    ),
                                  )
                                ]),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _KeepAlive(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Form(
                            key: _pageKeys[8],
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 200,
                                  child: Image.asset(
                                    'assets/sprayer/hinge_to_control_unit_sprayer.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, st) =>
                                        const Center(
                                      child: Icon(Icons.image_not_supported,
                                          size: 48),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _hingeToControlUnit,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Distance between hinge point and control unit mounting'),
                                      keyboardType: TextInputType.numberWithOptions(
                                          decimal: true),
                                      validator: (v) => (v == null || v.isEmpty)
                                          ? 'Enter hinge->control unit distance'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 110,
                                    child: DropdownButtonFormField<String>(
                                      value: _hingeToControlUnitUnit,
                                      items: const [
                                        DropdownMenuItem(value: 'm', child: Text('m')),
                                        DropdownMenuItem(value: 'in', child: Text('in')),
                                      ],
                                      onChanged: (v) => setState(() => _hingeToControlUnitUnit = v ?? 'm'),
                                      decoration: const InputDecoration(labelText: 'Unit'),
                                    ),
                                  )
                                ]),
                              ],
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 12.0),
                  child: Row(
                    children: [
                      if (_currentPage > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              final prev = _currentPage - 1;
                              _pageController.animateToPage(prev,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut);
                            },
                            child: const Text('Back'),
                          ),
                        ),
                      if (_currentPage > 0) const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  debugPrint(
                                      'CreateSprayerScreen: Save pressed, currentPage=$_currentPage');
                                  // ensure keyboard is dismissed so field values are committed
                                  FocusScope.of(context).unfocus();
                                  final key = _pageKeys[_currentPage];
                                  if (!(key.currentState?.validate() ?? false))
                                    return;
                                  if (_currentPage < 8) {
                                    final next = _currentPage + 1;
                                    _pageController.animateToPage(next,
                                        duration:
                                            const Duration(milliseconds: 250),
                                        curve: Curves.easeInOut);
                                    return;
                                  }

                                  // validate all pages before final save, with logging
                                  for (var i = 0; i < _pageKeys.length; i++) {
                                    debugPrint(
                                        'CreateSprayerScreen: validating page $i');
                                    final k = _pageKeys[i];
                                    final valid =
                                        k.currentState?.validate() ?? false;
                                    if (!valid) {
                                      final vals = {
                                        0: _name.text,
                                        1: _wheelDiameter.text,
                                        2: _screwsInWheel.text,
                                        3: _axleLength.text,
                                        4: _nozzleCount.text,
                                        5: _tankCapacity.text,
                                        6: _hingeToAxle.text,
                                        7: _hingeToNozzle.text,
                                        8: _hingeToControlUnit.text,
                                      };
                                      debugPrint(
                                          'CreateSprayerScreen: page $i invalid, values=$vals');
                                      _pageController.animateToPage(i,
                                          duration:
                                              const Duration(milliseconds: 250),
                                          curve: Curves.easeInOut);
                                      return;
                                    }
                                  }

                                  // final save
                                  setState(() => _isSaving = true);
                                  final ctrl =
                                      ref.read(equipmentControllerProvider);
                                  final navigator = Navigator.of(context);
                                  double? wheelDiameter;
                                  int? screwsInWheel;
                                  double? hingeToAxle;
                                  double? hingeToNozzle;
                                  double? hingeToControlUnit;
                                  double? axleLength;
                                  int? nozzleCount;
                                  double? tankCapacity;
                                  try {
                                    wheelDiameter =
                                        double.tryParse(_wheelDiameter.text);
                                    if (wheelDiameter != null) {
                                      if (_wheelDiameterUnit == 'in') {
                                        wheelDiameter = wheelDiameter * 0.0254;
                                      } else if (_wheelDiameterUnit == 'ft') {
                                        wheelDiameter = wheelDiameter * 0.3048;
                                      }
                                    }
                                  } catch (e, st) {
                                    debugPrint(
                                        'CreateSprayerScreen: parse wheelDiameter error: $e');
                                    debugPrint('stack: $st');
                                    wheelDiameter = null;
                                  }
                                  try {
                                    screwsInWheel =
                                        int.tryParse(_screwsInWheel.text);
                                  } catch (e, st) {
                                    debugPrint(
                                        'CreateSprayerScreen: parse screwsInWheel error: $e');
                                    debugPrint('stack: $st');
                                    screwsInWheel = null;
                                  }
                                  try {
                                    hingeToAxle =
                                        double.tryParse(_hingeToAxle.text);
                                    if (hingeToAxle != null) {
                                      if (_hingeToAxleUnit == 'in') {
                                        hingeToAxle = hingeToAxle * 0.0254;
                                      } else if (_hingeToAxleUnit == 'ft') {
                                        hingeToAxle = hingeToAxle * 0.3048;
                                      }
                                    }
                                  } catch (e, st) {
                                    debugPrint(
                                        'CreateSprayerScreen: parse hingeToAxle error: $e');
                                    debugPrint('stack: $st');
                                    hingeToAxle = null;
                                  }
                                  try {
                                    hingeToNozzle =
                                        double.tryParse(_hingeToNozzle.text);
                                    if (hingeToNozzle != null) {
                                      if (_hingeToNozzleUnit == 'in') {
                                        hingeToNozzle = hingeToNozzle * 0.0254;
                                      } else if (_hingeToNozzleUnit == 'ft') {
                                        hingeToNozzle = hingeToNozzle * 0.3048;
                                      }
                                    }
                                  } catch (e, st) {
                                    debugPrint(
                                        'CreateSprayerScreen: parse hingeToNozzle error: $e');
                                    debugPrint('stack: $st');
                                    hingeToNozzle = null;
                                  }
                                  try {
                                    hingeToControlUnit = double.tryParse(
                                        _hingeToControlUnit.text);
                                    if (hingeToControlUnit != null) {
                                      if (_hingeToControlUnitUnit == 'in') {
                                        hingeToControlUnit = hingeToControlUnit * 0.0254;
                                      } else if (_hingeToControlUnitUnit == 'ft') {
                                        hingeToControlUnit = hingeToControlUnit * 0.3048;
                                      }
                                    }
                                  } catch (e, st) {
                                    debugPrint(
                                        'CreateSprayerScreen: parse hingeToControlUnit error: $e');
                                    debugPrint('stack: $st');
                                    hingeToControlUnit = null;
                                  }

                                  try {
                                    axleLength =
                                        double.tryParse(_axleLength.text);
                                    if (axleLength != null) {
                                      if (_axleLengthUnit == 'in') {
                                        axleLength = axleLength * 0.0254;
                                      } else if (_axleLengthUnit == 'ft') {
                                        axleLength = axleLength * 0.3048;
                                      }
                                    }
                                  } catch (e, st) {
                                    debugPrint(
                                        'CreateSprayerScreen: parse axleLength error: $e');
                                    debugPrint('stack: $st');
                                    axleLength = null;
                                  }
                                  try {
                                    nozzleCount =
                                        int.tryParse(_nozzleCount.text);
                                  } catch (e, st) {
                                    debugPrint(
                                        'CreateSprayerScreen: parse nozzleCount error: $e');
                                    debugPrint('stack: $st');
                                    nozzleCount = null;
                                  }
                                  try {
                                    tankCapacity =
                                        double.tryParse(_tankCapacity.text);
                                  } catch (e, st) {
                                    debugPrint(
                                        'CreateSprayerScreen: parse tankCapacity error: $e');
                                    debugPrint('stack: $st');
                                    tankCapacity = null;
                                  }

                                  final currentUserId = ref
                                      .read(authServiceProvider)
                                      .currentUserId;
                                  try {
                                    if (isEditing) {
                                      final id = widget.existingData!['id']
                                              as String? ??
                                          DateTime.now()
                                              .millisecondsSinceEpoch
                                              .toString();
                                      final data = {
                                        'category': 'sprayer',
                                        'name': _name.text,
                                        'userId': currentUserId,
                                        'status': widget.existingData!['status']
                                                as String? ??
                                            'vacant',
                                        'wheelDiameter': wheelDiameter,
                                        'screwsInWheel': screwsInWheel,
                                        'hingeToAxle': hingeToAxle,
                                        'hingeToNozzle': hingeToNozzle,
                                        'hingeToControlUnit':
                                            hingeToControlUnit,
                                        'axleLength': axleLength,
                                        'nozzleCount': nozzleCount,
                                        'tankCapacity': tankCapacity,
                                      };
                                      await ctrl.update(id, data);
                                    } else {
                                      final id = DateTime.now()
                                          .millisecondsSinceEpoch
                                          .toString();
                                      final data = {
                                        'id': id,
                                        'category': 'sprayer',
                                        'name': _name.text,
                                        'userId': currentUserId,
                                        'status': 'vacant',
                                        'wheelDiameter': wheelDiameter,
                                        'screwsInWheel': screwsInWheel,
                                        'hingeToAxle': hingeToAxle,
                                        'hingeToNozzle': hingeToNozzle,
                                        'hingeToControlUnit':
                                            hingeToControlUnit,
                                        'axleLength': axleLength,
                                        'nozzleCount': nozzleCount,
                                        'tankCapacity': tankCapacity,
                                      };
                                      await ctrl.add(data);
                                    }
                                    if (!mounted) return;
                                    // hide spinner and show success snackbar
                                    if (mounted)
                                      setState(() => _isSaving = false);
                                    final msg = isEditing
                                        ? 'Sprayer updated'
                                        : 'Sprayer added';
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(msg)));
                                    await Future.delayed(
                                        const Duration(milliseconds: 700));
                                    if (!mounted) return;
                                    debugPrint(
                                        'CreateSprayerScreen: save successful');
                                    navigator.pop(true);
                                  } catch (e) {
                                    if (e is ApiException) {
                                      final err = ApiError.fromResponse(
                                          e.statusCode, e.body);
                                      showApiErrorSnackBar(context, err);
                                    } else {
                                      showGenericErrorSnackBar(
                                          context, e.toString());
                                    }

                                    if (mounted)
                                      setState(() => _isSaving = false);
                                  }
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24.0, vertical: 12.0),
                            child: Text(_currentPage < 8 ? 'Next' : 'Save'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isSaving)
              Positioned.fill(
                child: Container(
                  color: Colors.black45,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
          ]),
        ));
  }
}
