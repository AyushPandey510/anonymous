import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../theme.dart';
import '../data/location_service.dart';
import '../data/place_search_repository.dart';
import '../domain/geofence_validator.dart';
import '../domain/geo_point.dart';

class InteractiveGeofenceMap extends StatefulWidget {
  const InteractiveGeofenceMap({
    super.key,
    required this.point,
    required this.radiusMeters,
    required this.validation,
    required this.onPointChanged,
    required this.onAccuracyChanged,
  });

  final GeoPoint point;
  final int radiusMeters;
  final GeofenceValidationResult validation;
  final ValueChanged<GeoPoint> onPointChanged;
  final ValueChanged<double> onAccuracyChanged;

  @override
  State<InteractiveGeofenceMap> createState() => _InteractiveGeofenceMapState();
}

class _InteractiveGeofenceMapState extends State<InteractiveGeofenceMap> {
  final _mapController = MapController();
  final _searchController = TextEditingController();
  final _locationService = const SpaceLocationService();
  final _searchRepository = const PlaceSearchRepository();

  Timer? _debounce;
  List<PlaceSearchResult> _results = const [];
  bool _locating = false;
  bool _searching = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnUser());
  }

  @override
  void didUpdateWidget(covariant InteractiveGeofenceMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.point.latitude != widget.point.latitude ||
        oldWidget.point.longitude != widget.point.longitude) {
      _mapController.move(_latLng(widget.point), _mapController.camera.zoom);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final point = _latLng(widget.point);
    final decisionColor = _decisionColor(colors, widget.validation.decision);

    return Container(
      height: 360,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outline),
      ),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: point,
              initialZoom: 16,
              minZoom: 3,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) _selectPoint(camera.center);
              },
              onLongPress: (_, selected) =>
                  _moveTo(selected, zoom: _mapController.camera.zoom),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.space.space_mobile',
                tileBuilder: isDark ? _darkTileBuilder : null,
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: point,
                    radius: widget.radiusMeters.toDouble(),
                    useRadiusInMeter: true,
                    color: decisionColor.withValues(alpha: 0.12),
                    borderColor: decisionColor.withValues(alpha: 0.45),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: point,
                    width: 56,
                    height: 56,
                    child: Icon(
                      Icons.location_pin,
                      color: colors.accent,
                      size: 46,
                    ),
                  ),
                ],
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap',
                    textStyle: TextStyle(
                      color: colors.secondaryText.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _SearchBox(
              controller: _searchController,
              searching: _searching,
              onChanged: _onSearchChanged,
            ),
          ),
          if (_results.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              top: 66,
              child: _SearchResults(
                results: _results,
                onSelected: (result) {
                  _searchController.text = result.label;
                  setState(() => _results = const []);
                  _moveTo(_latLng(result.point), zoom: 17);
                },
              ),
            ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              children: [
                _MapIconButton(
                  icon: Icons.my_location_rounded,
                  loading: _locating,
                  onTap: _centerOnUser,
                ),
                const SizedBox(height: 8),
                _MapIconButton(
                  icon: Icons.add_rounded,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                ),
                const SizedBox(height: 8),
                _MapIconButton(
                  icon: Icons.remove_rounded,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 70,
            bottom: 12,
            child: _MapStatus(
              point: widget.point,
              radiusMeters: widget.radiusMeters,
              validation: widget.validation,
              status: _status,
            ),
          ),
        ],
      ),
    );
  }

  Widget _darkTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -0.55, 0, 0, 0, 150,
        0, -0.55, 0, 0, 150,
        0, 0, -0.55, 0, 150,
        0, 0, 0, 1, 0,
      ]),
      child: Opacity(opacity: 0.78, child: tileWidget),
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _results = const [];
        _status = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 380), () async {
      setState(() {
        _searching = true;
        _status = 'Searching...';
      });
      try {
        final results = await _searchRepository.search(query);
        if (!mounted) return;
        setState(() {
          _results = results;
          _status = results.isEmpty ? 'No matching places found' : null;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _results = const [];
          _status = 'Search is unavailable';
        });
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _centerOnUser() async {
    setState(() {
      _locating = true;
      _status = 'Locating...';
    });
    try {
      final fix = await _locationService.currentFix();
      widget.onAccuracyChanged(fix.accuracyMeters ?? 75);
      _moveTo(_latLng(fix.point), zoom: 17);
      if (!mounted) return;
      setState(
        () => _status = 'Accuracy ${fix.accuracyMeters?.round() ?? '?'}m',
      );
    } on SpaceLocationException catch (error) {
      if (!mounted) return;
      setState(() => _status = _permissionMessage(error.state));
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not get current location');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _moveTo(LatLng point, {required double zoom}) {
    _mapController.move(point, zoom);
    _selectPoint(point);
  }

  void _selectPoint(LatLng point) {
    widget.onPointChanged(
      GeoPoint(latitude: point.latitude, longitude: point.longitude),
    );
  }

  LatLng _latLng(GeoPoint point) => LatLng(point.latitude, point.longitude);

  String _permissionMessage(SpaceLocationPermissionState state) {
    return switch (state) {
      SpaceLocationPermissionState.granted => 'Location ready',
      SpaceLocationPermissionState.denied => 'Location permission denied',
      SpaceLocationPermissionState.deniedForever =>
        'Enable location in settings',
      SpaceLocationPermissionState.servicesDisabled =>
        'Location services are off',
      SpaceLocationPermissionState.restricted => 'Location is restricted',
    };
  }

  Color _decisionColor(SpaceColors colors, GeofenceDecision decision) {
    return switch (decision) {
      GeofenceDecision.inside => colors.accent,
      GeofenceDecision.nearBoundary => colors.warning,
      GeofenceDecision.outside => colors.dangerStrong,
      GeofenceDecision.lowAccuracy => colors.warning,
      GeofenceDecision.rejected => colors.dangerStrong,
    };
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.searching,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool searching;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 2, 10, 2),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            color: colors.secondaryText,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
              decoration: InputDecoration(
                hintText: 'Search address or paste coordinates',
                hintStyle: TextStyle(color: colors.disabled),
                border: InputBorder.none,
              ),
            ),
          ),
          if (searching)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.accent,
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.results, required this.onSelected});

  final List<PlaceSearchResult> results;
  final ValueChanged<PlaceSearchResult> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: results.length,
        separatorBuilder: (_, _) =>
            Divider(color: colors.outlineSubtle, height: 1),
        itemBuilder: (context, index) {
          final result = results[index];
          return ListTile(
            dense: true,
            leading: Icon(
              Icons.place_outlined,
              color: colors.accent,
              size: 19,
            ),
            title: Text(
              result.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
            subtitle: Text(
              '${result.point.latitude.toStringAsFixed(5)}, ${result.point.longitude.toStringAsFixed(5)}',
              style: TextStyle(color: colors.disabled, fontSize: 11),
            ),
            onTap: () => onSelected(result),
          );
        },
      ),
    );
  }
}

class _MapStatus extends StatelessWidget {
  const _MapStatus({
    required this.point,
    required this.radiusMeters,
    required this.validation,
    this.status,
  });

  final GeoPoint point;
  final int radiusMeters;
  final GeofenceValidationResult validation;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final text =
        status ??
        '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)} • ${radiusMeters}m';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline),
      ),
      child: Row(
        children: [
          Icon(
            validation.canParticipate
                ? Icons.verified_rounded
                : Icons.info_outline_rounded,
            color: validation.canParticipate
                ? colors.accent
                : colors.warning,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.secondaryText, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapIconButton extends StatelessWidget {
  const _MapIconButton({
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return IconButton(
      onPressed: loading ? null : onTap,
      style: IconButton.styleFrom(
        backgroundColor: colors.surface.withValues(alpha: 0.92),
        foregroundColor: colors.primaryText,
        disabledForegroundColor: colors.disabled,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outline),
        ),
      ),
      icon: loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.accent,
              ),
            )
          : Icon(icon, size: 20),
    );
  }
}

