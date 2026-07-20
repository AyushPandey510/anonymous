import 'geo_point.dart';

class LocationFix {
  const LocationFix({
    required this.point,
    required this.capturedAt,
    this.accuracyMeters,
  });

  final GeoPoint point;
  final DateTime capturedAt;
  final double? accuracyMeters;
}
