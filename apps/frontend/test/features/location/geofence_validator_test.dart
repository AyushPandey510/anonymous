import 'package:flutter_test/flutter_test.dart';
import 'package:space_mobile/features/location/domain/geofence.dart';
import 'package:space_mobile/features/location/domain/geofence_validator.dart';
import 'package:space_mobile/features/location/domain/geo_point.dart';
import 'package:space_mobile/features/location/domain/location_fix.dart';

void main() {
  const validator = GeofenceValidator();
  const geofence = CircleGeofence(
    center: GeoPoint(latitude: 12.9716, longitude: 77.5946),
    radiusMeters: 100,
  );

  test('validates a high confidence inside fix', () {
    final result = validator.validate(
      geofence: geofence,
      current: fix(12.97161, 77.59461, 12),
    );

    expect(result.decision, GeofenceDecision.inside);
    expect(result.lifecycleState, SessionLifecycleState.inside);
    expect(result.confidence, LocationConfidence.high);
    expect(result.canParticipate, isTrue);
  });

  test('allows near-boundary fixes within accuracy tolerance', () {
    final result = validator.validate(
      geofence: geofence,
      current: fix(12.97279, 77.5946, 35),
    );

    expect(result.decision, GeofenceDecision.nearBoundary);
    expect(result.lifecycleState, SessionLifecycleState.nearBoundary);
    expect(result.canParticipate, isTrue);
  });

  test('rejects low-accuracy fixes for joining', () {
    final result = validator.validate(
      geofence: geofence,
      current: fix(12.97161, 77.59461, 120),
    );

    expect(result.decision, GeofenceDecision.lowAccuracy);
    expect(result.reason, 'accuracy_too_low');
  });

  test('rejects impossible jumps', () {
    final now = DateTime.utc(2026, 7, 20, 10);

    final result = validator.validate(
      geofence: geofence,
      previous: LocationFix(
        point: const GeoPoint(latitude: 12.9716, longitude: 77.5946),
        accuracyMeters: 12,
        capturedAt: now,
      ),
      current: LocationFix(
        point: const GeoPoint(latitude: 13.1, longitude: 77.5946),
        accuracyMeters: 12,
        capturedAt: now.add(const Duration(seconds: 3)),
      ),
    );

    expect(result.decision, GeofenceDecision.rejected);
    expect(result.reason, 'impossible_location_jump');
  });

  test('buffers outside readings before entering grace period', () {
    final result = validator.validate(
      geofence: geofence,
      history: const GeofenceValidationHistory(
        consecutiveOutside: 1,
        previousLifecycle: SessionLifecycleState.inside,
      ),
      current: fix(12.9740, 77.5946, 12),
    );

    expect(result.decision, GeofenceDecision.nearBoundary);
    expect(result.reason, 'outside_buffer_pending');
    expect(result.consecutiveOutside, 2);
    expect(result.canParticipate, isTrue);
  });

  test('moves to grace period after repeated outside readings', () {
    final result = validator.validate(
      geofence: geofence,
      history: const GeofenceValidationHistory(
        consecutiveOutside: 2,
        previousLifecycle: SessionLifecycleState.inside,
      ),
      current: fix(12.9740, 77.5946, 12),
    );

    expect(result.decision, GeofenceDecision.outside);
    expect(result.lifecycleState, SessionLifecycleState.gracePeriod);
    expect(result.consecutiveOutside, 3);
    expect(result.canParticipate, isTrue);
  });

  test('rejects mock-location signal', () {
    final result = validator.validate(
      geofence: geofence,
      current: fix(12.97161, 77.59461, 12),
      mockLocation: true,
    );

    expect(result.decision, GeofenceDecision.rejected);
    expect(result.reason, 'mock_location_detected');
    expect(result.canParticipate, isFalse);
  });

  test('rejects excessive speed between fixes', () {
    final now = DateTime.utc(2026, 7, 20, 10);

    final result = validator.validate(
      geofence: geofence,
      history: GeofenceValidationHistory(
        previousFix: LocationFix(
          point: const GeoPoint(latitude: 12.9716, longitude: 77.5946),
          accuracyMeters: 12,
          capturedAt: now,
        ),
        previousLifecycle: SessionLifecycleState.inside,
      ),
      current: LocationFix(
        point: const GeoPoint(latitude: 12.9900, longitude: 77.5946),
        accuracyMeters: 12,
        capturedAt: now.add(const Duration(seconds: 20)),
      ),
    );

    expect(result.decision, GeofenceDecision.rejected);
    expect(result.reason, 'excessive_speed');
    expect(result.speedMetersPerSecond, isNotNull);
  });
}

LocationFix fix(double latitude, double longitude, double accuracyMeters) {
  return LocationFix(
    point: GeoPoint(latitude: latitude, longitude: longitude),
    accuracyMeters: accuracyMeters,
    capturedAt: DateTime.utc(2026, 7, 20, 10),
  );
}
