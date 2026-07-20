import 'geo_point.dart';

class CircleGeofence {
  const CircleGeofence({required this.center, required this.radiusMeters});

  static const minRadiusMeters = 30;
  static const maxRadiusMeters = 300;

  final GeoPoint center;
  final int radiusMeters;

  bool get isValid {
    return center.isValid &&
        radiusMeters >= minRadiusMeters &&
        radiusMeters <= maxRadiusMeters;
  }

  CircleGeofence copyWith({GeoPoint? center, int? radiusMeters}) {
    return CircleGeofence(
      center: center ?? this.center,
      radiusMeters: radiusMeters ?? this.radiusMeters,
    );
  }
}
