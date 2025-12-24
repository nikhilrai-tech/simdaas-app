import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/equipment_providers.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'dart:convert';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/utils/api_error.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';

class CreateEquipmentScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existingData;
  const CreateEquipmentScreen({super.key, this.existingData});

  @override
  ConsumerState<CreateEquipmentScreen> createState() =>
      _CreateEquipmentScreenState();
}

class _CreateEquipmentScreenState extends ConsumerState<CreateEquipmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String _category = 'tractor';
  final _mountingHeight = TextEditingController();
  final _lidarNozzleDistance = TextEditingController();
  final _ultrasonicDistance = TextEditingController();
  final _wheelDiameter = TextEditingController();
  final _screwsInWheel = TextEditingController();
  final _axleLength = TextEditingController();
  final _hingeToAxle = TextEditingController();
  final _hingeToNozzle = TextEditingController();
  final _hingeToControlUnit = TextEditingController();
  final _macAddress = TextEditingController();
  final _linkedSprayerId = TextEditingController();
  final _linkedTractorId = TextEditingController();
  final _controlUnitId = TextEditingController();
  String _sprayerType = 'lidar';
  // Unit selectors for fields that are stored in meters. If user enters in
  // inches, we'll convert to meters on save.
  String _mountingHeightUnit = 'm';
  String _lidarNozzleDistanceUnit = 'm';
  String _ultrasonicDistanceUnit = 'm';
  String _wheelDiameterUnit = 'm';
  String _axleLengthUnit = 'm';
  String _hingeToAxleUnit = 'm';
  String _hingeToNozzleUnit = 'm';
  String _hingeToControlUnitUnit = 'm';

  @override
  Widget build(BuildContext context) {
    // if editing, prefill controllers
    final isEditing = widget.existingData != null;
    if (isEditing) {
      final ex = widget.existingData!;
      _category = ex['category'] as String? ?? _category;
      _name.text = ex['name'] as String? ?? '';
      if (ex['mountingHeight'] != null)
        _mountingHeight.text = '${ex['mountingHeight']}';
      if (ex['lidarNozzleDistance'] != null)
        _lidarNozzleDistance.text = '${ex['lidarNozzleDistance']}';
      if (ex['ultrasonicDistance'] != null)
        _ultrasonicDistance.text = '${ex['ultrasonicDistance']}';
      if (ex['wheelDiameter'] != null)
        _wheelDiameter.text = '${ex['wheelDiameter']}';
      if (ex['screwsInWheel'] != null)
        _screwsInWheel.text = '${ex['screwsInWheel']}';
      if (ex['axleLength'] != null) _axleLength.text = '${ex['axleLength']}';
      if (ex['hingeToAxle'] != null) _hingeToAxle.text = '${ex['hingeToAxle']}';
      if (ex['hingeToNozzle'] != null)
        _hingeToNozzle.text = '${ex['hingeToNozzle']}';
      if (ex['hingeToControlUnit'] != null)
        _hingeToControlUnit.text = '${ex['hingeToControlUnit']}';
      if (ex['macAddress'] != null)
        _macAddress.text = ex['macAddress'] as String? ?? '';
      if (ex['linkedSprayerId'] != null)
        _linkedSprayerId.text = ex['linkedSprayerId'] as String? ?? '';
      if (ex['linkedTractorId'] != null)
        _linkedTractorId.text = ex['linkedTractorId'] as String? ?? '';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Create Equipment')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: Column(children: [
            DropdownButtonFormField<String>(
              value: _category,
              items: const [
                DropdownMenuItem(value: 'tractor', child: Text('Tractor')),
                DropdownMenuItem(value: 'sprayer', child: Text('Sprayer')),
                DropdownMenuItem(
                    value: 'control_unit', child: Text('Control Unit')),
              ],
              onChanged: (v) => setState(() => _category = v ?? 'tractor'),
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Equipment Name'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter name' : null),
            const SizedBox(height: 12),
            if (_category == 'sprayer') ...[
              DropdownButtonFormField<String>(
                value: _sprayerType,
                items: const [
                  DropdownMenuItem(value: 'lidar', child: Text('Lidar')),
                  DropdownMenuItem(
                      value: 'ultrasonic', child: Text('Ultrasonic')),
                ],
                onChanged: (v) => setState(() => _sprayerType = v ?? 'lidar'),
                decoration:
                    const InputDecoration(labelText: 'Sprayer sensor type'),
              ),
              const SizedBox(height: 8),
              if (_sprayerType == 'lidar') ...[
                Row(children: [
                  Expanded(
                    child: TextFormField(
                        controller: _mountingHeight,
                        decoration: const InputDecoration(
                            labelText: 'Mounting height of lidar'),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true)),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      value: _mountingHeightUnit,
                      items: const [
                        DropdownMenuItem(value: 'm', child: Text('m')),
                        DropdownMenuItem(value: 'in', child: Text('in')),
                        DropdownMenuItem(value: 'ft', child: Text('ft')),
                      ],
                      onChanged: (v) =>
                          setState(() => _mountingHeightUnit = v ?? 'm'),
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  )
                ]),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                        controller: _lidarNozzleDistance,
                        decoration: const InputDecoration(
                            labelText: 'Distance between lidar and nozzle'),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true)),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      value: _lidarNozzleDistanceUnit,
                      items: const [
                        DropdownMenuItem(value: 'm', child: Text('m')),
                        DropdownMenuItem(value: 'in', child: Text('in')),
                        DropdownMenuItem(value: 'ft', child: Text('ft')),
                      ],
                      onChanged: (v) =>
                          setState(() => _lidarNozzleDistanceUnit = v ?? 'm'),
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  )
                ]),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                        controller: _hingeToAxle,
                        decoration: const InputDecoration(
                            labelText: 'Distance between hinge point and axle'),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true)),
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
                      onChanged: (v) =>
                          setState(() => _hingeToAxleUnit = v ?? 'm'),
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  )
                ]),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                        controller: _hingeToNozzle,
                        decoration: const InputDecoration(
                            labelText:
                                'Distance between hinge point and nozzle'),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true)),
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
                      onChanged: (v) =>
                          setState(() => _hingeToNozzleUnit = v ?? 'm'),
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  )
                ]),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                        controller: _hingeToControlUnit,
                        decoration: const InputDecoration(
                            labelText:
                                'Distance between hinge point and control unit mounting'),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true)),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      value: _hingeToControlUnitUnit,
                      items: const [
                        DropdownMenuItem(value: 'm', child: Text('m')),
                        DropdownMenuItem(value: 'in', child: Text('in')),
                        DropdownMenuItem(value: 'ft', child: Text('ft')),
                      ],
                      onChanged: (v) =>
                          setState(() => _hingeToControlUnitUnit = v ?? 'm'),
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  )
                ]),
              ] else ...[
                Row(children: [
                  Expanded(
                    child: TextFormField(
                        controller: _ultrasonicDistance,
                        decoration: const InputDecoration(
                            labelText: 'Distance of sensor from center line'),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true)),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      value: _ultrasonicDistanceUnit,
                      items: const [
                        DropdownMenuItem(value: 'm', child: Text('m')),
                        DropdownMenuItem(value: 'in', child: Text('in')),
                      ],
                      onChanged: (v) =>
                          setState(() => _ultrasonicDistanceUnit = v ?? 'm'),
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  )
                ]),
              ],
            ] else if (_category == 'tractor') ...[
              Row(children: [
                Expanded(
                  child: TextFormField(
                      controller: _wheelDiameter,
                      decoration:
                          const InputDecoration(labelText: 'Wheel diameter'),
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true)),
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
                    onChanged: (v) =>
                        setState(() => _wheelDiameterUnit = v ?? 'm'),
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                )
              ]),
              TextFormField(
                  controller: _screwsInWheel,
                  decoration: const InputDecoration(
                      labelText: 'Number of screws/Nuts in wheel'),
                  keyboardType: TextInputType.number),
              Row(children: [
                Expanded(
                  child: TextFormField(
                      controller: _axleLength,
                      decoration:
                          const InputDecoration(labelText: 'Axle length'),
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true)),
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
                    onChanged: (v) =>
                        setState(() => _axleLengthUnit = v ?? 'm'),
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                )
              ]),
            ] else if (_category == 'control_unit') ...[
              TextFormField(
                  controller: _controlUnitId,
                  decoration:
                      const InputDecoration(labelText: 'Control unit ID'),
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Enter control unit id'
                      : null),
              TextFormField(
                  controller: _macAddress,
                  decoration: const InputDecoration(labelText: 'MAC address'),
                  keyboardType: TextInputType.text),
              TextFormField(
                  controller: _linkedSprayerId,
                  decoration:
                      const InputDecoration(labelText: 'Linked sprayer ID'),
                  keyboardType: TextInputType.text),
              TextFormField(
                  controller: _linkedTractorId,
                  decoration:
                      const InputDecoration(labelText: 'Linked tractor ID'),
                  keyboardType: TextInputType.text),
            ] else if (_category == 'tractor')
              ...[],
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  final ctrl = ref.read(equipmentControllerProvider);
                  double? mountingHeight;
                  double? lidarNozzleDistance;
                  double? wheelDiameter;
                  int? screwsInWheel;
                  double? ultrasonicDistance;
                  double? axleLength;
                  double? hingeToAxle;
                  double? hingeToNozzle;
                  double? hingeToControlUnit;
                  String? macAddress;
                  String? linkedSprayerId;
                  String? linkedTractorId;
                  try {
                    mountingHeight = double.tryParse(_mountingHeight.text);
                    if (mountingHeight != null) {
                      if (_mountingHeightUnit == 'in') {
                        mountingHeight = mountingHeight * 0.0254;
                      } else if (_mountingHeightUnit == 'ft') {
                        mountingHeight = mountingHeight * 0.3048;
                      }
                    }
                  } catch (e, st) {
                    debugPrint(
                        'CreateEquipmentScreen: parse mountingHeight error: $e');
                    debugPrint('stack: $st');
                    mountingHeight = null;
                  }
                  try {
                    ultrasonicDistance =
                        double.tryParse(_ultrasonicDistance.text);
                    if (ultrasonicDistance != null) {
                      if (_ultrasonicDistanceUnit == 'in') {
                        ultrasonicDistance = ultrasonicDistance * 0.0254;
                      } else if (_ultrasonicDistanceUnit == 'ft') {
                        ultrasonicDistance = ultrasonicDistance * 0.3048;
                      }
                    }
                  } catch (e, st) {
                    debugPrint(
                        'CreateEquipmentScreen: parse ultrasonicDistance error: $e');
                    debugPrint('stack: $st');
                    ultrasonicDistance = null;
                  }
                  try {
                    lidarNozzleDistance =
                        double.tryParse(_lidarNozzleDistance.text);
                    if (lidarNozzleDistance != null) {
                      if (_lidarNozzleDistanceUnit == 'in') {
                        lidarNozzleDistance = lidarNozzleDistance * 0.0254;
                      } else if (_lidarNozzleDistanceUnit == 'ft') {
                        lidarNozzleDistance = lidarNozzleDistance * 0.3048;
                      }
                    }
                  } catch (e, st) {
                    debugPrint(
                        'CreateEquipmentScreen: parse lidarNozzleDistance error: $e');
                    debugPrint('stack: $st');
                    lidarNozzleDistance = null;
                  }
                  try {
                    wheelDiameter = double.tryParse(_wheelDiameter.text);
                    if (wheelDiameter != null) {
                      if (_wheelDiameterUnit == 'in') {
                        wheelDiameter = wheelDiameter * 0.0254;
                      } else if (_wheelDiameterUnit == 'ft') {
                        wheelDiameter = wheelDiameter * 0.3048;
                      }
                    }
                  } catch (e, st) {
                    debugPrint(
                        'CreateEquipmentScreen: parse wheelDiameter error: $e');
                    debugPrint('stack: $st');
                    wheelDiameter = null;
                  }
                  try {
                    screwsInWheel = int.tryParse(_screwsInWheel.text);
                  } catch (e, st) {
                    debugPrint(
                        'CreateEquipmentScreen: parse screwsInWheel error: $e');
                    debugPrint('stack: $st');
                    screwsInWheel = null;
                  }
                  try {
                    axleLength = double.tryParse(_axleLength.text);
                    if (axleLength != null) {
                      if (_axleLengthUnit == 'in') {
                        axleLength = axleLength * 0.0254;
                      } else if (_axleLengthUnit == 'ft') {
                        axleLength = axleLength * 0.3048;
                      }
                    }
                  } catch (e, st) {
                    debugPrint(
                        'CreateEquipmentScreen: parse axleLength error: $e');
                    debugPrint('stack: $st');
                    axleLength = null;
                  }
                  try {
                    hingeToAxle = double.tryParse(_hingeToAxle.text);
                    if (hingeToAxle != null) {
                      if (_hingeToAxleUnit == 'in') {
                        hingeToAxle = hingeToAxle * 0.0254;
                      } else if (_hingeToAxleUnit == 'ft') {
                        hingeToAxle = hingeToAxle * 0.3048;
                      }
                    }
                  } catch (e, st) {
                    debugPrint(
                        'CreateEquipmentScreen: parse hingeToAxle error: $e');
                    debugPrint('stack: $st');
                    hingeToAxle = null;
                  }
                  try {
                    hingeToNozzle = double.tryParse(_hingeToNozzle.text);
                    if (hingeToNozzle != null) {
                      if (_hingeToNozzleUnit == 'in') {
                        hingeToNozzle = hingeToNozzle * 0.0254;
                      } else if (_hingeToNozzleUnit == 'ft') {
                        hingeToNozzle = hingeToNozzle * 0.3048;
                      }
                    }
                  } catch (e, st) {
                    debugPrint(
                        'CreateEquipmentScreen: parse hingeToNozzle error: $e');
                    debugPrint('stack: $st');
                    hingeToNozzle = null;
                  }
                  try {
                    hingeToControlUnit =
                        double.tryParse(_hingeToControlUnit.text);
                    if (hingeToControlUnit != null) {
                      if (_hingeToControlUnitUnit == 'in') {
                        hingeToControlUnit = hingeToControlUnit * 0.0254;
                      } else if (_hingeToControlUnitUnit == 'ft') {
                        hingeToControlUnit = hingeToControlUnit * 0.3048;
                      }
                    }
                  } catch (e, st) {
                    debugPrint(
                        'CreateEquipmentScreen: parse hingeToControlUnit error: $e');
                    debugPrint('stack: $st');
                    hingeToControlUnit = null;
                  }
                  macAddress =
                      _macAddress.text.isEmpty ? null : _macAddress.text;
                  linkedSprayerId = _linkedSprayerId.text.isEmpty
                      ? null
                      : _linkedSprayerId.text;
                  linkedTractorId = _linkedTractorId.text.isEmpty
                      ? null
                      : _linkedTractorId.text;

                  final currentUserId =
                      ref.read(authServiceProvider).currentUserId;
                  try {
                    if (isEditing) {
                      final id = widget.existingData!['id'] as String? ??
                          DateTime.now().millisecondsSinceEpoch.toString();
                      final data = {
                        'category': _category,
                        'name': _name.text,
                        'userId': currentUserId,
                        'status': widget.existingData!['status'] as String? ??
                            'vacant',
                        'controlUnitId': _controlUnitId.text.isEmpty
                            ? null
                            : _controlUnitId.text,
                        'mountingHeight': mountingHeight,
                        'lidarNozzleDistance': lidarNozzleDistance,
                        'ultrasonicDistance': ultrasonicDistance,
                        'wheelDiameter': wheelDiameter,
                        'screwsInWheel': screwsInWheel,
                        'axleLength': axleLength,
                        'hingeToAxle': hingeToAxle,
                        'hingeToNozzle': hingeToNozzle,
                        'hingeToControlUnit': hingeToControlUnit,
                        'macAddress': macAddress,
                        'linkedSprayerId': linkedSprayerId,
                        'linkedTractorId': linkedTractorId,
                      };
                      await ctrl.update(id, data);
                    } else {
                      final id =
                          DateTime.now().millisecondsSinceEpoch.toString();
                      final data = {
                        'id': id,
                        'category': _category,
                        'name': _name.text,
                        'userId': currentUserId,
                        'status': 'vacant',
                        'controlUnitId': _controlUnitId.text.isEmpty
                            ? null
                            : _controlUnitId.text,
                        'mountingHeight': mountingHeight,
                        'lidarNozzleDistance': lidarNozzleDistance,
                        'ultrasonicDistance': ultrasonicDistance,
                        'wheelDiameter': wheelDiameter,
                        'screwsInWheel': screwsInWheel,
                        'axleLength': axleLength,
                        'hingeToAxle': hingeToAxle,
                        'hingeToNozzle': hingeToNozzle,
                        'hingeToControlUnit': hingeToControlUnit,
                        'macAddress': macAddress,
                        'linkedSprayerId': linkedSprayerId,
                        'linkedTractorId': linkedTractorId,
                      };
                      await ctrl.add(data);
                    }
                    if (!mounted) return;
                    Navigator.of(context).pop(true);
                  } catch (e) {
                    if (e is ApiException) {
                      final err = ApiError.fromResponse(e.statusCode, e.body);
                      showApiErrorSnackBar(context, err);
                    } else {
                      showGenericErrorSnackBar(context, e.toString());
                    }
                  }
                },
                child: const Text('Save'))
          ]),
        ),
      ),
    );
  }
}
