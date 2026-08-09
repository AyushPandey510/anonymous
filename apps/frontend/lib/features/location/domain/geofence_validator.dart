import 'dart:math' as math;

import 'geofence.dart';
import 'geo_point.dart';
import 'location_fix.dart';

const _earthRadiusMeters = 6371000.0;
const _maxAccuracyToleranceMeters = 35.0;
const _maxAcceptableJoinAccuracyMeters = 75.0;
const _exitBufferMeters = 20.0;
const _requiredOutsideReadings = 3;
const _jumpThresholdMeters = 500.0;
const _jumpWindowSeconds = 5;
const _walkingSpeedRejectMetersPerSecond = 55.56;

enum GeofenceDecision { inside, nearBoundary, outside, lowAccuracy, rejected }

enum LocationConfidence { high, medium, low }

enum SessionLifecycleState {
  joining,
  inside,
  nearBoundary,
  gracePeriod,
  outside,
  expired,
}

class GeofenceValidationResult {
  const GeofenceValidationResult({
    required this.decision,
    required this.lifecycleState,
    required this.distanceMeters,
    required this.effectiveRadiusMeters,
    required this.confidence,
    required this.consecutiveOutside,
    this.speedMetersPerSecond,
    this.reason,
  });

  final GeofenceDecision decision;
  final SessionLifecycleState lifecycleState;
  final double distanceMeters;
  final double effectiveRadiusMeters;
  final double? speedMetersPerSecond;
  final LocationConfidence confidence;
  final int consecutiveOutside;
  final String? reason;

  bool get canParticipate {
    return decision == GeofenceDecision.inside ||
        decision == GeofenceDecision.nearBoundary ||
        lifecycleState == SessionLifecycleState.inside ||
        lifecycleState == SessionLifecycleState.nearBoundary ||
        lifecycleState == SessionLifecycleState.gracePeriod;
  }
}

class GeofenceValidationHistory {
  const GeofenceValidationHistory({
    this.previousFix,
    this.recentFixes = const [],
    this.consecutiveOutside = 0,
    this.previousLifecycle = SessionLifecycleState.joining,
  });

  final LocationFix? previousFix;
  final List<LocationFix> recentFixes;
  final int consecutiveOutside;
  final SessionLifecycleState previousLifecycle;
}

class GeofenceValidator {
  const GeofenceValidator();

  GeofenceValidationResult validate({
    required CircleGeofence geofence,
    required LocationFix current,
    LocationFix? previous,
    GeofenceValidationHistory? history,
    bool mockLocation = false,
  }) {
    final validationHistory =
        history ??
        GeofenceValidationHistory(
          previousFix: previous,
          recentFixes: previous == null ? const [] : [previous],
        );

    if (!geofence.center.isValid ||
        !current.point.isValid ||
        geofence.radiusMeters <= 0) {
      return _rejected('invalid_coordinate');
    }

    final accuracy = current.accuracyMeters;
    if (accuracy != null && (!accuracy.isFinite || accuracy < 0)) {
      return _rejected('invalid_accuracy');
    }

    final speed = validationHistory.previousFix == null
        ? null
        : _speedMetersPerSecond(validationHistory.previousFix!, current);
    if (mockLocation) {
      return _rejectedWithDistance(
        geofence,
        current,
        speed,
        'mock_location_detected',
      );
    }

    if (validationHistory.previousFix != null &&
        _isImpossibleJump(validationHistory.previousFix!, current)) {
      return _rejectedWithDistance(
        geofence,
        current,
        speed,
        'impossible_location_jump',
      );
    }

    if (speed != null && speed > _walkingSpeedRejectMetersPerSecond) {
      return _rejectedWithDistance(geofence, current, speed, 'excessive_speed');
    }

    final usableAccuracy = accuracy ?? _maxAcceptableJoinAccuracyMeters + 1;
    final smoothedFix = _medianSmoothedFix(
      current,
      validationHistory.recentFixes,
    );
    final distance = distanceMeters(geofence.center, smoothedFix.point);
    final effectiveRadius =
        geofence.radiusMeters.toDouble() +
        math.min(usableAccuracy, _maxAccuracyToleranceMeters);

    if (usableAccuracy > _maxAcceptableJoinAccuracyMeters) {
      return GeofenceValidationResult(
        decision: GeofenceDecision.lowAccuracy,
        lifecycleState: validationHistory.previousLifecycle,
        distanceMeters: distance,
        effectiveRadiusMeters: effectiveRadius,
        speedMetersPerSecond: speed,
        confidence: LocationConfidence.low,
        consecutiveOutside: validationHistory.consecutiveOutside,
        reason: 'accuracy_too_low',
      );
    }

    final rawDecision = _classifyDistance(geofence, distance, effectiveRadius);
    final buffered = _bufferOutside(
      rawDecision,
      validationHistory.consecutiveOutside,
    );

    return GeofenceValidationResult(
      decision: buffered.$1,
      lifecycleState: _lifecycleForDecision(
        buffered.$1,
        validationHistory.previousLifecycle,
      ),
      distanceMeters: distance,
      effectiveRadiusMeters: effectiveRadius,
      speedMetersPerSecond: speed,
      confidence: _confidenceForAccuracy(usableAccuracy),
      consecutiveOutside: buffered.$2,
      reason: _reasonForDecision(rawDecision, buffered.$1),
    );
  }

  double distanceMeters(GeoPoint a, GeoPoint b) {
    final dLat = _radians(b.latitude - a.latitude);
    final dLon = _radians(b.longitude - a.longitude);
    final lat1 = _radians(a.latitude);
    final lat2 = _radians(b.latitude);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    return 2 * _earthRadiusMeters * math.asin(math.sqrt(h));
  }

  GeofenceDecision _classifyDistance(
    CircleGeofence geofence,
    double distance,
    double effectiveRadius,
  ) {
    final enterThreshold = geofence.radiusMeters;
    final exitThreshold = geofence.radiusMeters + _exitBufferMeters;
    if (distance <= enterThreshold) return GeofenceDecision.inside;
    if (distance <= math.max(effectiveRadius, exitThreshold)) {
      return GeofenceDecision.nearBoundary;
    }
    return GeofenceDecision.outside;
  }

  (GeofenceDecision, int) _bufferOutside(
    GeofenceDecision rawDecision,
    int consecutiveOutside,
  ) {
    if (rawDecision == GeofenceDecision.outside) {
      final nextCount = consecutiveOutside + 1;
      if (nextCount >= _requiredOutsideReadings) {
        return (GeofenceDecision.outside, nextCount);
      }
      return (GeofenceDecision.nearBoundary, nextCount);
    }
    if (rawDecision == GeofenceDecision.inside ||
        rawDecision == GeofenceDecision.nearBoundary) {
      return (rawDecision, 0);
    }
    return (rawDecision, consecutiveOutside);
  }

  SessionLifecycleState _lifecycleForDecision(
    GeofenceDecision decision,
    SessionLifecycleState previous,
  ) {
    return switch (decision) {
      GeofenceDecision.inside => SessionLifecycleState.inside,
      GeofenceDecision.nearBoundary => SessionLifecycleState.nearBoundary,
      GeofenceDecision.outside => switch (previous) {
        SessionLifecycleState.inside ||
        SessionLifecycleState.nearBoundary ||
        SessionLifecycleState.gracePeriod => SessionLifecycleState.gracePeriod,
        _ => SessionLifecycleState.outside,
      },
      GeofenceDecision.lowAccuracy => previous,
      GeofenceDecision.rejected => SessionLifecycleState.outside,
    };
  }

  String? _reasonForDecision(
    GeofenceDecision rawDecision,
    GeofenceDecision bufferedDecision,
  ) {
    if (rawDecision == GeofenceDecision.outside &&
        bufferedDecision == GeofenceDecision.nearBoundary) {
      return 'outside_buffer_pending';
    }
    if (bufferedDecision == GeofenceDecision.nearBoundary) {
      return 'within_hysteresis_or_accuracy_tolerance';
    }
    return null;
  }

  LocationFix _medianSmoothedFix(
    LocationFix current,
    List<LocationFix> recent,
  ) {
    final latitudes = [
      current.point.latitude,
      for (final fix in recent.take(3)) fix.point.latitude,
    ]..sort();
    final longitudes = [
      current.point.longitude,
      for (final fix in recent.take(3)) fix.point.longitude,
    ]..sort();
    return LocationFix(
      point: GeoPoint(
        latitude: latitudes[latitudes.length ~/ 2],
        longitude: longitudes[longitudes.length ~/ 2],
      ),
      accuracyMeters: current.accuracyMeters,
      capturedAt: current.capturedAt,
    );
  }

  double? _speedMetersPerSecond(LocationFix previous, LocationFix current) {
    final elapsedMs = current.capturedAt
        .difference(previous.capturedAt)
        .inMilliseconds
        .abs();
    if (elapsedMs <= 0) return null;
    return distanceMeters(previous.point, current.point) / (elapsedMs / 1000);
  }

  bool _isImpossibleJump(LocationFix previous, LocationFix current) {
    final seconds = current.capturedAt
        .difference(previous.capturedAt)
        .inSeconds
        .abs();
    return seconds <= _jumpWindowSeconds &&
        distanceMeters(previous.point, current.point) > _jumpThresholdMeters;
  }

  LocationConfidence _confidenceForAccuracy(double accuracyMeters) {
    if (accuracyMeters <= 25) return LocationConfidence.high;
    if (accuracyMeters <= _maxAcceptableJoinAccuracyMeters) {
      return LocationConfidence.medium;
    }
    return LocationConfidence.low;
  }

  GeofenceValidationResult _rejected(String reason) {
    return GeofenceValidationResult(
      decision: GeofenceDecision.rejected,
      lifecycleState: SessionLifecycleState.outside,
      distanceMeters: 0,
      effectiveRadiusMeters: 0,
      confidence: LocationConfidence.low,
      consecutiveOutside: 0,
      reason: reason,
    );
  }

  GeofenceValidationResult _rejectedWithDistance(
    CircleGeofence geofence,
    LocationFix current,
    double? speed,
    String reason,
  ) {
    return GeofenceValidationResult(
      decision: GeofenceDecision.rejected,
      lifecycleState: SessionLifecycleState.outside,
      distanceMeters: distanceMeters(geofence.center, current.point),
      effectiveRadiusMeters: geofence.radiusMeters.toDouble(),
      speedMetersPerSecond: speed,
      confidence: LocationConfidence.low,
      consecutiveOutside: 0,
      reason: reason,
    );
  }

  double _radians(double degrees) => degrees * math.pi / 180;
}
