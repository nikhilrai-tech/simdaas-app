class Report {
  final String id;
  final String plotName;
  final double area;
  final String operatorName;
  final String boundaryName;
  final double materialApplied;
  final double avgFlowRate;
  final double percentCovered;
  final Duration timeTaken;
  final DateTime startTime;
  final DateTime endTime;
  final Duration ptoActiveTime;
  final double distanceTravelled;
  final double distanceWithPtoOn;
  final double distanceSprayed;
  final String mixDetails;
  final double avgSpeed;
  final Duration timeSaved;

  const Report({
    required this.id,
    required this.plotName,
    required this.area,
    required this.operatorName,
    required this.boundaryName,
    required this.materialApplied,
    required this.avgFlowRate,
    required this.percentCovered,
    required this.timeTaken,
    required this.startTime,
    required this.endTime,
    required this.ptoActiveTime,
    required this.distanceTravelled,
    required this.distanceWithPtoOn,
    required this.distanceSprayed,
    required this.mixDetails,
    required this.avgSpeed,
    required this.timeSaved,
  });
}
