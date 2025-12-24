import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/equipment_providers.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'dart:convert';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/utils/api_error.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';

// Small helper to keep PageView pages alive so their FormState is available
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

class CreateTractorScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existingData;
  const CreateTractorScreen({super.key, this.existingData});

  @override
  ConsumerState<CreateTractorScreen> createState() =>
      _CreateTractorScreenState();
}

class _CreateTractorScreenState extends ConsumerState<CreateTractorScreen> {
  bool _debugShown = false;
  final _formKey = GlobalKey<FormState>();
  late final List<GlobalKey<FormState>> _pageKeys;
  final _name = TextEditingController();
  final _wheelDiameter = TextEditingController();
  final _screwsInWheel = TextEditingController();
  final _axleLength = TextEditingController();
  // Unit selectors for meter fields
  String _wheelDiameterUnit = 'm';
  String _axleLengthUnit = 'm';
  final _pageController = PageController();
  int _currentPage = 0;
  bool _isSaving = false;

  @override
  void dispose() {
    _name.dispose();
    _wheelDiameter.dispose();
    _screwsInWheel.dispose();
    _axleLength.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _pageKeys = List.generate(4, (_) => GlobalKey<FormState>());
    if (widget.existingData != null) {
      final ex = widget.existingData!;
      // Prefill controllers once (do not set in build to avoid overwriting user input)
      _name.text = ex['name'] as String? ?? '';
      if (ex['wheelDiameter'] != null)
        _wheelDiameter.text = '${ex['wheelDiameter']}';
      if (ex['screwsInWheel'] != null)
        _screwsInWheel.text = '${ex['screwsInWheel']}';
      if (ex['axleLength'] != null) _axleLength.text = '${ex['axleLength']}';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_debugShown && mounted) {
          debugPrint(
              'CreateTractorScreen existingData: ${widget.existingData}');
          _debugShown = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingData != null;

    final totalPages = 4;
    return Scaffold(
        appBar: AppBar(title: Text(isEditing ? 'Edit Tractor' : 'Add Tractor')),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Progress
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 8.0),
                    child: LinearProgressIndicator(
                      value: (1.0 * (_currentPage + 1)) / totalPages,
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
                                  // Illustration for this field (asset name: tractor_name.png)
                                  SizedBox(
                                    height: 200,
                                    child: Image.asset(
                                      'assets/tractor/tractor_name.png',
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
                                        labelText: 'Tractor name'),
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
                                      'assets/tractor/wheel_diameter.png',
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
                                        keyboardType:
                                            TextInputType.numberWithOptions(
                                                decimal: true),
                                        validator: (v) =>
                                            (v == null || v.isEmpty)
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
                                          DropdownMenuItem(
                                              value: 'm', child: Text('m')),
                                          DropdownMenuItem(
                                              value: 'in', child: Text('in')),
                                          DropdownMenuItem(
                                              value: 'ft', child: Text('ft')),
                                        ],
                                        onChanged: (v) => setState(() =>
                                            _wheelDiameterUnit = v ?? 'm'),
                                        decoration: const InputDecoration(
                                            labelText: 'Unit'),
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
                                      'assets/tractor/screws_in_wheel.png',
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
                                      'assets/tractor/axle_length.png',
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
                                        keyboardType:
                                            TextInputType.numberWithOptions(
                                                decimal: true),
                                        validator: (v) =>
                                            (v == null || v.isEmpty)
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
                                          DropdownMenuItem(
                                              value: 'm', child: Text('m')),
                                          DropdownMenuItem(
                                              value: 'in', child: Text('in')),
                                          DropdownMenuItem(
                                              value: 'ft', child: Text('ft')),
                                        ],
                                        onChanged: (v) => setState(
                                            () => _axleLengthUnit = v ?? 'm'),
                                        decoration: const InputDecoration(
                                            labelText: 'Unit'),
                                      ),
                                    )
                                  ]),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Navigation buttons
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
                                    // validate current page
                                    final key = _pageKeys[_currentPage];
                                    if (!(key.currentState?.validate() ??
                                        false)) return;
                                    if (_currentPage < totalPages - 1) {
                                      final next = _currentPage + 1;
                                      _pageController.animateToPage(next,
                                          duration:
                                              const Duration(milliseconds: 250),
                                          curve: Curves.easeInOut);
                                      return;
                                    }

                                    debugPrint(
                                        'CreateTractorScreen: Save pressed, currentPage=$_currentPage');
                                    // ensure keyboard is dismissed so field values are committed
                                    FocusScope.of(context).unfocus();
                                    // validate all pages before final save, with logging to find failures
                                    for (var i = 0; i < totalPages; i++) {
                                      debugPrint(
                                          'CreateTractorScreen: validating page $i');
                                      final k = _pageKeys[i];
                                      final valid =
                                          k.currentState?.validate() ?? false;
                                      if (!valid) {
                                        // Log controller values for troubleshooting
                                        final vals = {
                                          0: _name.text,
                                          1: _wheelDiameter.text,
                                          2: _screwsInWheel.text,
                                          3: _axleLength.text,
                                        };
                                        debugPrint(
                                            'CreateTractorScreen: page $i invalid, values=$vals');
                                        _pageController.animateToPage(i,
                                            duration: const Duration(
                                                milliseconds: 250),
                                            curve: Curves.easeInOut);
                                        return; // stop save until user fills required fields
                                      }
                                    }

                                    // final save
                                    final ctrl =
                                        ref.read(equipmentControllerProvider);
                                    final navigator = Navigator.of(context);
                                    double? wheelDiameter;
                                    int? screwsInWheel;
                                    double? axleLength;
                                    try {
                                      wheelDiameter =
                                          double.tryParse(_wheelDiameter.text);
                                      if (wheelDiameter != null) {
                                        if (_wheelDiameterUnit == 'in') {
                                          wheelDiameter =
                                              wheelDiameter * 0.0254;
                                        } else if (_wheelDiameterUnit == 'ft') {
                                          wheelDiameter =
                                              wheelDiameter * 0.3048;
                                        }
                                      }
                                    } catch (e, st) {
                                      debugPrint(
                                          'CreateTractorScreen: parse wheelDiameter error: $e');
                                      debugPrint('stack: $st');
                                      wheelDiameter = null;
                                    }
                                    try {
                                      screwsInWheel =
                                          int.tryParse(_screwsInWheel.text);
                                    } catch (e, st) {
                                      debugPrint(
                                          'CreateTractorScreen: parse screwsInWheel error: $e');
                                      debugPrint('stack: $st');
                                      screwsInWheel = null;
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
                                          'CreateTractorScreen: parse axleLength error: $e');
                                      debugPrint('stack: $st');
                                      axleLength = null;
                                    }

                                    final currentUserId = ref
                                        .read(authServiceProvider)
                                        .currentUserId;
                                    try {
                                      setState(() => _isSaving = true);
                                      if (isEditing) {
                                        final id = widget.existingData!['id']
                                                as String? ??
                                            DateTime.now()
                                                .millisecondsSinceEpoch
                                                .toString();
                                        final data = {
                                          'category': 'tractor',
                                          'name': _name.text,
                                          'userId': currentUserId,
                                          'status':
                                              widget.existingData!['status']
                                                      as String? ??
                                                  'vacant',
                                          'wheelDiameter': wheelDiameter,
                                          'screwsInWheel': screwsInWheel,
                                          'axleLength': axleLength,
                                        };
                                        await ctrl.update(id, data);
                                      } else {
                                        final id = DateTime.now()
                                            .millisecondsSinceEpoch
                                            .toString();
                                        final data = {
                                          'id': id,
                                          'category': 'tractor',
                                          'name': _name.text,
                                          'userId': currentUserId,
                                          'status': 'vacant',
                                          'wheelDiameter': wheelDiameter,
                                          'screwsInWheel': screwsInWheel,
                                          'axleLength': axleLength,
                                        };
                                        await ctrl.add(data);
                                      }
                                      if (!mounted) return;
                                      // hide spinner and show success snackbar
                                      if (mounted)
                                        setState(() => _isSaving = false);
                                      final msg = isEditing
                                          ? 'Tractor updated'
                                          : 'Tractor added';
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                              SnackBar(content: Text(msg)));
                                      await Future.delayed(
                                          const Duration(milliseconds: 700));
                                      if (!mounted) return;
                                      debugPrint(
                                          'CreateTractorScreen: save successful');
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
                                    } finally {
                                      if (mounted)
                                        setState(() => _isSaving = false);
                                    }
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0, vertical: 12.0),
                              child: Text(_currentPage < totalPages - 1
                                  ? 'Next'
                                  : 'Save'),
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
            ],
          ),
        ));
  }
}
