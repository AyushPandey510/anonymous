import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/geo_point.dart';

class PlaceSearchResult {
  const PlaceSearchResult({
    required this.label,
    required this.point,
    this.type,
  });

  final String label;
  final GeoPoint point;
  final String? type;
}

class PlaceSearchRepository {
  const PlaceSearchRepository({this.client});

  final http.Client? client;

  Future<List<PlaceSearchResult>> search(String query) async {
    final coordinate = _parseCoordinates(query);
    if (coordinate != null) {
      return [
        PlaceSearchResult(
          label: 'Coordinates',
          point: coordinate,
          type: 'coordinates',
        ),
      ];
    }

    final normalized = query.trim();
    if (normalized.length < 3) return const [];

    final activeClient = client ?? http.Client();
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': normalized,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '5',
    });

    try {
      final response = await activeClient.get(
        uri,
        headers: const {
          'User-Agent': 'SpaceMobile/0.1 contact@example.com',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const PlaceSearchException('search_unavailable');
      }
      final body = jsonDecode(response.body);
      if (body is! List) return const [];

      return body
          .whereType<Map<String, dynamic>>()
          .map((json) {
            final latitude = double.tryParse('${json['lat']}');
            final longitude = double.tryParse('${json['lon']}');
            final label = '${json['display_name'] ?? ''}'.trim();
            if (latitude == null || longitude == null || label.isEmpty) {
              return null;
            }
            return PlaceSearchResult(
              label: label,
              point: GeoPoint(latitude: latitude, longitude: longitude),
              type: '${json['type'] ?? ''}'.trim(),
            );
          })
          .nonNulls
          .toList();
    } finally {
      if (client == null) activeClient.close();
    }
  }

  GeoPoint? _parseCoordinates(String query) {
    final parts = query
        .split(RegExp(r'[, ]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length != 2) return null;

    final latitude = double.tryParse(parts[0]);
    final longitude = double.tryParse(parts[1]);
    if (latitude == null || longitude == null) return null;

    final point = GeoPoint(latitude: latitude, longitude: longitude);
    return point.isValid ? point : null;
  }
}

class PlaceSearchException implements Exception {
  const PlaceSearchException(this.code);

  final String code;
}
