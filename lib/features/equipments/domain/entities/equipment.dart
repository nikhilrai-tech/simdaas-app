class EquipmentEntity {
  final String id;
  final String category; // e.g., tractor, sprayer
  final String name;
  final String? userId;
  final String? status; // e.g., 'vacant', 'assigned', 'in_service'

  // sprayer-specific fields
  final double? mountingHeight; // meters
  final double? lidarNozzleDistance; // meters
  final double?
      ultrasonicDistance; // meters from center line (for ultrasonic sensors)
  final double? wheelDiameter; // meters
  final int? screwsInWheel;
  // control unit specific
  final String? controlUnitId;
  // tractor-specific
  final double? axleLength;
  // sprayer nozzle / tank
  final int? nozzleCount;
  final double? tankCapacity; // liters
  // sprayer hinge distances
  final double? hingeToAxle;
  final double? hingeToNozzle;
  final double? hingeToControlUnit;
  // control unit specifics
  final String? macAddress;
  final String? linkedSprayerId;
  final String? linkedTractorId;
  final String? linkedPlotId;
  // timestamps
  final DateTime? createdAt;
  final DateTime? updatedAt;
  // legacy mounting/w lidar/ultrasonic kept for compatibility

  EquipmentEntity({
    required this.id,
    required this.category,
    required this.name,
    this.userId,
    this.status,
    this.mountingHeight,
    this.lidarNozzleDistance,
    this.ultrasonicDistance,
    this.wheelDiameter,
    this.screwsInWheel,
    this.controlUnitId,
    this.axleLength,
    this.nozzleCount,
    this.tankCapacity,
    this.hingeToAxle,
    this.hingeToNozzle,
    this.hingeToControlUnit,
    this.macAddress,
    this.linkedSprayerId,
    this.linkedTractorId,
    this.linkedPlotId,
    this.createdAt,
    this.updatedAt,
  });
}

class TractorEntity extends EquipmentEntity {
  TractorEntity({
    required super.id,
    required super.category,
    required super.name,
    super.userId,
    super.status,
    super.wheelDiameter,
    super.screwsInWheel,
    super.axleLength,
  });
}

class SprayerEntity extends EquipmentEntity {
  SprayerEntity({
    required super.id,
    required super.category,
    required super.name,
    super.userId,
    super.status,
    super.mountingHeight,
    super.lidarNozzleDistance,
    super.ultrasonicDistance,
    super.hingeToAxle,
    super.hingeToNozzle,
    super.hingeToControlUnit,
    super.axleLength,
    super.nozzleCount,
    super.tankCapacity,
  });
}

class ControlUnitEntity extends EquipmentEntity {
  ControlUnitEntity({
    required super.id,
    required super.category,
    required super.name,
    super.userId,
    super.status,
    super.controlUnitId,
    super.macAddress,
    super.linkedSprayerId,
    super.linkedTractorId,
    super.linkedPlotId,
    super.lidarNozzleDistance,
    super.mountingHeight,
    super.ultrasonicDistance,
  });
}
