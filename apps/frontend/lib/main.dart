import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:space_mobile/config/app_config.dart';
import 'package:space_mobile/features/location/domain/geofence.dart';
import 'package:space_mobile/features/location/domain/geofence_validator.dart';
import 'package:space_mobile/features/location/domain/geo_point.dart';
import 'package:space_mobile/features/location/domain/location_fix.dart';
import 'package:space_mobile/features/location/presentation/interactive_geofence_map.dart';
import 'package:space_mobile/features/location/presentation/location_selection_screen.dart';
import 'package:space_mobile/features/splash/animated_splash_screen.dart';
import 'package:space_mobile/services/api_client.dart';
import 'package:space_mobile/services/api_service.dart';
import 'package:space_mobile/services/auth_service.dart';
import 'package:space_mobile/services/chat_socket.dart';
import 'package:space_mobile/theme.dart';

void main() {
  runApp(const SpaceApp());
}

String get defaultApiBaseUrl => AppConfig.apiBaseUrl;

class SpaceApp extends StatefulWidget {
  const SpaceApp({super.key});

  @override
  State<SpaceApp> createState() => _SpaceAppState();
}

class _SpaceAppState extends State<SpaceApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _themeMode == ThemeMode.dark;
    return MaterialApp(
      title: 'Space',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: buildSpaceTheme(Brightness.light),
      darkTheme: buildSpaceTheme(Brightness.dark),
      home: AppLoader(onToggleTheme: _toggleTheme, isDark: isDark),
    );
  }
}

class AppLoader extends StatefulWidget {
  const AppLoader({super.key, required this.onToggleTheme, required this.isDark});

  final VoidCallback onToggleTheme;
  final bool isDark;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  late final String _baseUrl;
  late final ApiClient _client;
  late final AuthService _auth;
  late final ApiService _api;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _baseUrl = defaultApiBaseUrl;
    _client = ApiClient(_baseUrl);
    _auth = AuthService(_client);
    _api = ApiService(_client);
    _init();
  }

  Future<void> _init() async {
    debugPrint('[Space App] 🚀 Initializing backend connection: $_baseUrl ...');
    final stopwatch = Stopwatch()..start();
    try {
      await _auth.init();
      final loggedIn = await _auth.ensureLoggedIn();
      if (!mounted) return;
      if (loggedIn) {
        debugPrint('[Space App] ✅ Session ready! Entering Space.');
        final elapsed = stopwatch.elapsedMilliseconds;
        if (elapsed < 2600) {
          await Future.delayed(Duration(milliseconds: 2600 - elapsed));
        }
        if (!mounted) return;
        setState(() => _ready = true);
      } else {
        final reason = _auth.lastError ?? 'Connection refused';
        debugPrint('[Space App] ❌ Authentication failed for $_baseUrl: $reason');
        setState(() {
          _error = 'Could not connect to server at $_baseUrl\n\n$reason';
        });
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[Space App] ❌ Connection error for $_baseUrl: $e');
      setState(() => _error = 'Could not connect to server at $_baseUrl\n\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    if (_error != null) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.danger.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cloud_off_rounded,
                    size: 40,
                    color: colors.dangerStrong,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Connection Error',
                  style: SpaceTypography.headingMedium(color: colors.primaryText),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: SpaceTypography.bodyMedium(color: colors.secondaryText),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _ready = false;
                    });
                    _init();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      return const AnimatedSplashScreen();
    }

    return SpaceShell(
      api: _api,
      auth: _auth,
      onToggleTheme: widget.onToggleTheme,
      isDark: widget.isDark,
    );
  }
}

enum AppScreen { location, discovery, chat, mySpaces }

class SpaceShell extends StatefulWidget {
  const SpaceShell({
    super.key,
    required this.api,
    required this.auth,
    required this.onToggleTheme,
    required this.isDark,
  });

  final ApiService api;
  final AuthService auth;
  final VoidCallback onToggleTheme;
  final bool isDark;

  @override
  State<SpaceShell> createState() => _SpaceShellState();
}

class _SpaceShellState extends State<SpaceShell> {
  AppScreen _screen = AppScreen.location;
  GeoPoint? _userLocation;
  Space? _activeSpace;
  String? _anonymousName;
  String? _sessionId;
  Timer? _geofenceTimer;

  @override
  void initState() {
    super.initState();
    _checkSavedLocation();
  }

  @override
  void dispose() {
    _geofenceTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkSavedLocation() async {
    final saved = await LocationSelectionScreen.getSavedLocation();
    if (!mounted) return;
    if (saved != null) {
      setState(() {
        _userLocation = saved;
        _screen = AppScreen.discovery;
      });
    }
  }

  void _startGeofenceMonitoring() {
    _geofenceTimer?.cancel();
    _geofenceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkGeofence(),
    );
  }

  Future<void> _checkGeofence() async {
    if (_activeSpace == null || _sessionId == null) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
      final result = await widget.api.validateLocation(
        spaceId: _activeSpace!.id,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );

      if (!mounted) return;

      if (result.lifecycleState == 'outside' ||
          result.lifecycleState == 'expired') {
        _geofenceTimer?.cancel();
        _showExitDialog();
      }
    } catch (_) {}
  }

  void _showExitDialog() {
    final colors = SpaceColors.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.outline),
        ),
        title: Text(
          'Left Space Area',
          style: SpaceTypography.headingMedium(color: colors.primaryText),
        ),
        content: Text(
          'You have moved outside the Space geofence. You will be removed from this Space.',
          style: SpaceTypography.bodyMedium(color: colors.secondaryText),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _onGeofenceExit();
            },
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onBackToDashboard() {
    setState(() {
      _screen = AppScreen.mySpaces;
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (_screen) {
      AppScreen.location => LocationSelectionScreen(
          onLocationSelected: _onLocationSelected,
          onToggleTheme: widget.onToggleTheme,
          isDark: widget.isDark,
        ),
      AppScreen.discovery || AppScreen.mySpaces => _buildHomeTabs(),
      AppScreen.chat => ChatScreen(
          space: _activeSpace!,
          sessionId: _sessionId!,
          anonymousName: _anonymousName!,
          api: widget.api,
          onExited: _onGeofenceExit,
          onLeave: _onLeaveSpace,
          onBack: _onBackToDashboard,
          onToggleTheme: widget.onToggleTheme,
          isDark: widget.isDark,
        ),
    };
  }

  Widget _buildHomeTabs() {
    final colors = SpaceColors.of(context);
    final selectedIndex = _screen == AppScreen.discovery ? 0 : 1;
    return Scaffold(
      backgroundColor: colors.background,
      body: _screen == AppScreen.discovery
          ? SpaceDiscoveryScreen(
              api: widget.api,
              latitude: _userLocation!.latitude,
              longitude: _userLocation!.longitude,
              onJoinSpace: _onJoinSpace,
              onCreateSpace: _onCreateSpace,
              onChangeLocation: _onChangeLocation,
              onLogout: _onLogout,
              onToggleTheme: widget.onToggleTheme,
              isDark: widget.isDark,
            )
          : MySpacesScreen(
              api: widget.api,
              onOpenSpace: _onJoinSpace,
              onToggleTheme: widget.onToggleTheme,
              isDark: widget.isDark,
            ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colors.navBackground,
          border: Border(top: BorderSide(color: colors.outline, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _screen = index == 0 ? AppScreen.discovery : AppScreen.mySpaces;
            });
          },
          backgroundColor: colors.navBackground,
          indicatorColor: colors.accent.withValues(alpha: 0.16),
          height: 64,
          elevation: 0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.radar_outlined, color: colors.disabled, size: 21),
              selectedIcon: Icon(Icons.radar_rounded, color: colors.secondaryAccent, size: 21),
              label: 'Discovery',
            ),
            NavigationDestination(
              icon: Icon(Icons.forum_outlined, color: colors.disabled, size: 21),
              selectedIcon: Icon(Icons.forum_rounded, color: colors.secondaryAccent, size: 21),
              label: 'My Spaces',
            ),
          ],
        ),
      ),
    );
  }

  void _onLocationSelected(GeoPoint point) {
    setState(() {
      _userLocation = point;
      _screen = AppScreen.discovery;
    });
  }

  Future<bool> _onJoinSpace(Space space) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final session = await widget.api.joinSpace(
        space.id,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );

      setState(() {
        _activeSpace = space;
        _anonymousName = session.anonymousId;
        _sessionId = session.id;
        _screen = AppScreen.chat;
      });

      _startGeofenceMonitoring();
      return true;
    } catch (e) {
      if (mounted) {
        final colors = SpaceColors.of(context);
        final message = e is ApiException && e.statusCode == 403
            ? 'You need to be inside the space area to join it'
            : 'Could not join: ${e.toString()}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: SpaceTypography.bodyMedium(color: colors.primaryText)),
            backgroundColor: colors.surface2,
          ),
        );
      }
      return false;
    }
  }

  void _onCreateSpace() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CreateSpaceFlow(
          api: widget.api,
          userLocation: _userLocation!,
          onCreated: (space) {
            Navigator.of(context).pop();
            _onJoinSpace(space);
          },
          onToggleTheme: widget.onToggleTheme,
          isDark: widget.isDark,
        ),
      ),
    );
  }

  void _onChangeLocation() async {
    await LocationSelectionScreen.clearLocation();
    if (!mounted) return;
    setState(() => _screen = AppScreen.location);
  }

  void _onLogout() {
    setState(() {
      _activeSpace = null;
      _anonymousName = null;
      _sessionId = null;
      _screen = AppScreen.discovery;
    });
  }

  void _onGeofenceExit() {
    if (_activeSpace != null) {
      widget.api.leaveSpace(_activeSpace!.id);
    }
    setState(() {
      _activeSpace = null;
      _anonymousName = null;
      _sessionId = null;
      _screen = AppScreen.discovery;
    });
  }

  void _onLeaveSpace() {
    if (_activeSpace != null) {
      widget.api.leaveSpace(_activeSpace!.id);
    }
    _geofenceTimer?.cancel();
    setState(() {
      _activeSpace = null;
      _anonymousName = null;
      _sessionId = null;
      _screen = AppScreen.discovery;
    });
  }
}

class _CreateSpaceFlow extends StatelessWidget {
  const _CreateSpaceFlow({
    required this.api,
    required this.userLocation,
    required this.onCreated,
    required this.onToggleTheme,
    required this.isDark,
  });

  final ApiService api;
  final GeoPoint userLocation;
  final ValueChanged<Space> onCreated;
  final VoidCallback onToggleTheme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return CreateSpaceScreen(
      api: api,
      initialLocation: userLocation,
      onCreated: onCreated,
      onToggleTheme: onToggleTheme,
      isDark: isDark,
    );
  }
}

class CreateSpaceScreen extends StatefulWidget {
  const CreateSpaceScreen({
    super.key,
    required this.api,
    required this.initialLocation,
    required this.onCreated,
    this.onToggleTheme,
    this.isDark = true,
  });

  final ApiService api;
  final GeoPoint initialLocation;
  final ValueChanged<Space> onCreated;
  final VoidCallback? onToggleTheme;
  final bool isDark;

  @override
  State<CreateSpaceScreen> createState() => _CreateSpaceScreenState();
}

class _CreateSpaceScreenState extends State<CreateSpaceScreen> {
  final _nameController = TextEditingController();
  final _validator = const GeofenceValidator();
  bool _isPrivate = false;
  double _radius = 120;
  late GeoPoint _selectedPoint;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialLocation;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final geofence = CircleGeofence(
      center: _selectedPoint,
      radiusMeters: _radius.round(),
    );
    final currentFix = LocationFix(
      point: _selectedPoint,
      accuracyMeters: 18,
      capturedAt: DateTime.now().toUtc(),
    );
    final validation = _validator.validate(
      geofence: geofence,
      current: currentFix,
    );

    return Scaffold(
      backgroundColor: colors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.3,
            colors: [colors.gradientTop, colors.gradientBottom],
            stops: const [0, 0.65],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(bottom: BorderSide(color: colors.outline, width: 1)),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.surface2,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.outline),
                        ),
                        child: Icon(Icons.close_rounded, color: colors.primaryText, size: 18),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Create Space',
                        style: SpaceTypography.headingSmall(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.onToggleTheme != null)
                      IconButton(
                        onPressed: widget.onToggleTheme,
                        icon: Icon(
                          widget.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                          color: colors.secondaryText,
                          size: 20,
                        ),
                        tooltip: widget.isDark ? 'Light mode' : 'Dark mode',
                      ),
                  ],
                ),
              ),

              // Scrollable Form Content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                  children: [
                    // 1. Identity Heading
                    Text(
                      '1. Identity',
                      style: SpaceTypography.headingSmall(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Identity Card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: colors.outline),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SPACE NAME',
                            style: SpaceTypography.technical(
                              color: colors.secondaryText,
                              fontSize: 11,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: colors.surface2,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colors.outline),
                            ),
                            child: TextField(
                              controller: _nameController,
                              style: SpaceTypography.bodyLarge(
                                color: colors.primaryText,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.tag_rounded, color: colors.disabled, size: 20),
                                hintText: 'e.g. Neon District Lounge',
                                hintStyle: SpaceTypography.bodyMedium(color: colors.disabled),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'VISIBILITY',
                            style: SpaceTypography.technical(
                              color: colors.secondaryText,
                              fontSize: 11,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _VisibilityOptionPill(
                                  label: 'Public',
                                  icon: Icons.public_rounded,
                                  selected: !_isPrivate,
                                  onTap: () => setState(() => _isPrivate = false),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _VisibilityOptionPill(
                                  label: 'Invite Only',
                                  icon: Icons.lock_outline_rounded,
                                  selected: _isPrivate,
                                  onTap: () => setState(() => _isPrivate = true),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // 2. Geofence Heading & Status Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '2. Geofence',
                          style: SpaceTypography.headingSmall(
                            color: colors.primaryText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (validation.canParticipate ? colors.tertiary : colors.warning)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: (validation.canParticipate ? colors.tertiary : colors.warning)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: validation.canParticipate ? colors.tertiary : colors.warning,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (validation.canParticipate ? colors.tertiary : colors.warning)
                                          .withValues(alpha: 0.6),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                validation.canParticipate ? 'Inside bounds' : 'Check bounds',
                                style: SpaceTypography.technical(
                                  color: validation.canParticipate ? colors.tertiary : colors.warning,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Geofence Card with Map and Slider
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: colors.outline),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Interactive Map
                          Container(
                            height: 220,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: colors.outline),
                            ),
                            child: InteractiveGeofenceMap(
                              point: _selectedPoint,
                              radiusMeters: _radius.round(),
                              validation: validation,
                              onPointChanged: (point) {
                                setState(() {
                                  _selectedPoint = point;
                                });
                              },
                              onAccuracyChanged: (_) {},
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Radius Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'RADIUS',
                                style: SpaceTypography.technical(
                                  color: colors.secondaryText,
                                  fontSize: 11,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: colors.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  '${_radius.round()}m',
                                  style: SpaceTypography.technical(
                                    color: colors.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                '${CircleGeofence.minRadiusMeters}m',
                                style: SpaceTypography.technical(color: colors.disabled, fontSize: 11),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    activeTrackColor: colors.accent,
                                    inactiveTrackColor: const Color(0xFF252B33),
                                    thumbColor: const Color(0xFFAFC5FF),
                                    overlayColor: colors.accent.withValues(alpha: 0.15),
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                  ),
                                  child: Slider(
                                    value: _radius,
                                    min: CircleGeofence.minRadiusMeters.toDouble(),
                                    max: CircleGeofence.maxRadiusMeters.toDouble(),
                                    divisions: CircleGeofence.maxRadiusMeters - CircleGeofence.minRadiusMeters,
                                    onChanged: (value) => setState(() => _radius = value),
                                  ),
                                ),
                              ),
                              Text(
                                '${CircleGeofence.maxRadiusMeters}m',
                                style: SpaceTypography.technical(color: colors.disabled, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Initialize Space Button
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [colors.accent, colors.secondaryAccent],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.accent.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: FilledButton(
                        onPressed: _creating ? null : _createSpace,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: _creating
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.onAccent,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Initialize Space',
                                    style: SpaceTypography.headingSmall(
                                      color: colors.onAccent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('🚀', style: TextStyle(fontSize: 16)),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createSpace() async {
    setState(() => _creating = true);
    try {
      final response = await widget.api.createSpace(
        name: _nameController.text.trim().isEmpty
            ? 'Untitled Space'
            : _nameController.text.trim(),
        visibility: _isPrivate ? 'private' : 'public',
        latitude: _selectedPoint.latitude,
        longitude: _selectedPoint.longitude,
        radiusMeters: _radius.round(),
      );

      if (!mounted) return;
      widget.onCreated(
        Space(
          id: response['id'] as String,
          name: response['name'] as String,
          visibility: response['visibility'] as String,
          latitude: (response['latitude'] as num).toDouble(),
          longitude: (response['longitude'] as num).toDouble(),
          radiusMeters: response['radius_meters'] as int,
          createdAt: DateTime.parse(response['created_at'] as String),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final colors = SpaceColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create: ${e.toString()}', style: SpaceTypography.bodyMedium(color: colors.primaryText)),
          backgroundColor: colors.surface2,
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }
}

class _VisibilityOptionPill extends StatelessWidget {
  const _VisibilityOptionPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? colors.accent.withValues(alpha: 0.12) : colors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? colors.accent : colors.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? colors.accent : colors.disabled,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: SpaceTypography.bodyMedium(
                color: selected ? colors.primaryText : colors.secondaryText,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.space,
    required this.sessionId,
    required this.anonymousName,
    required this.api,
    required this.onExited,
    required this.onLeave,
    this.onBack,
    this.onToggleTheme,
    this.isDark = true,
    this.socket,
  });

  final Space space;
  final String sessionId;
  final String anonymousName;
  final ApiService api;
  final VoidCallback onExited;
  final VoidCallback onLeave;
  final VoidCallback? onBack;
  final VoidCallback? onToggleTheme;
  final bool isDark;
  final ChatSocket? socket;

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _messages = <ChatMessage>[];
  final _messageIds = <String>{};
  bool _loadingMessages = true;
  ChatMessage? _replyingTo;
  late final ChatSocket _socket;

  @override
  void initState() {
    super.initState();
    _socket = widget.socket ??
        ChatSocket(
          baseUrl: widget.api.client.baseUrl,
          getAccessToken: () => widget.api.client.accessToken ?? '',
          spaceId: widget.space.id,
        );
    _socket.events.listen(_onWsEvent, onError: (_) {});
    _loadMessages();
    _socket.connect();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.socket == null) _socket.dispose();
    super.dispose();
  }

  void _onWsEvent(WsEvent event) {
    switch (event) {
      case WsMessageEvent(:final message):
        _onIncomingMessage(message);
      case WsReactionEvent(:final messageId, :final emoji, :final count):
        _onReaction(messageId, emoji, count);
    }
  }

  void _onIncomingMessage(MessageData message) {
    if (!mounted || _messageIds.contains(message.id)) return;
    _messageIds.add(message.id);
    final colors = SpaceColors.of(context);
    setState(() {
      _messages.add(ChatMessage(
        id: message.id,
        name: message.anonymousId,
        text: message.content,
        replyTo: message.replyTo,
        replyText: message.replyContent,
        color: colors.accent,
        reactions: message.reactions.fold<Map<String, int>>(
          {},
          (map, r) => map..[r.emoji] = r.count,
        ),
      ));
    });
  }

  void _onReaction(String messageId, String emoji, int count) {
    if (!mounted) return;
    for (final message in _messages) {
      if (message.id == messageId) {
        setState(() => message.reactions[emoji] = count);
        return;
      }
    }
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await widget.api.getMessages(widget.space.id);
      if (!mounted) return;
      final colors = SpaceColors.of(context);
      setState(() {
        for (final m in msgs) {
          if (_messageIds.add(m.id)) {
            _messages.add(ChatMessage(
              id: m.id,
              name: m.anonymousId,
              text: m.content,
              replyTo: m.replyTo,
              replyText: m.replyContent,
              color: colors.accent,
              reactions: m.reactions.fold<Map<String, int>>(
                {},
                (map, r) => map..[r.emoji] = r.count,
              ),
            ));
          }
        }
        _loadingMessages = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final replyTo = _replyingTo;
    _controller.clear();
    setState(() => _replyingTo = null);

    try {
      final saved = await widget.api.sendMessage(
        widget.space.id,
        widget.sessionId,
        text,
        replyTo: replyTo?.id,
      );
      _onIncomingMessage(saved);
    } catch (_) {
      if (mounted && replyTo != null) setState(() => _replyingTo = replyTo);
    }
  }

  void _startReply(ChatMessage message) {
    setState(() => _replyingTo = message);
  }

  Future<void> _addReaction(ChatMessage message, String emoji) async {
    try {
      await widget.api.reactToMessage(message.id, widget.sessionId, emoji);
    } catch (_) {}
  }

  void _showMessageActions(ChatMessage message) {
    final colors = SpaceColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.outline),
                  ),
                  child: Text(
                    message.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SpaceTypography.bodyMedium(color: colors.primaryText),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final emoji in _reactionEmojis)
                      _ReactionButton(
                        emoji: emoji,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _addReaction(message, emoji);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.surface2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.reply_rounded, color: colors.accent, size: 18),
                  ),
                  title: Text('Reply', style: SpaceTypography.bodyLarge(color: colors.primaryText, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startReply(message);
                  },
                ),
                if (message.name == widget.anonymousName)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.delete_outline_rounded, color: colors.danger, size: 18),
                    ),
                    title: Text('Delete', style: SpaceTypography.bodyLarge(color: colors.danger, fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _confirmDelete(message);
                    },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.surface2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.flag_outlined, color: colors.secondaryText, size: 18),
                  ),
                  title: Text('Report', style: SpaceTypography.bodyLarge(color: colors.primaryText, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showReportOptions(message);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(ChatMessage message) async {
    final colors = SpaceColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.outline),
        ),
        title: Text(
          'Delete message?',
          style: SpaceTypography.headingMedium(color: colors.primaryText),
        ),
        content: Text(
          'This removes the message for everyone. Available within 15 minutes of sending.',
          style: SpaceTypography.bodyMedium(color: colors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: SpaceTypography.bodyMedium(color: colors.secondaryText)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colors.danger,
              foregroundColor: colors.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.api.deleteMessage(message.id);
      if (!mounted) return;
      setState(() {
        _messages.remove(message);
        _messageIds.remove(message.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Message deleted', style: SpaceTypography.bodyMedium(color: colors.primaryText)),
          backgroundColor: colors.surface2,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final messageText = e.statusCode == 403
          ? 'Only your own messages can be deleted'
          : 'Could not delete message';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messageText, style: SpaceTypography.bodyMedium(color: colors.primaryText)),
          backgroundColor: colors.surface2,
        ),
      );
    }
  }

  void _showReportOptions(ChatMessage message) {
    final colors = SpaceColors.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.outline),
        ),
        title: Text(
          'Report message',
          style: SpaceTypography.headingMedium(color: colors.primaryText),
        ),
        children: [
          for (final reason in _reportReasons)
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _sendReport(message, reason);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(reason, style: SpaceTypography.bodyLarge(color: colors.primaryText)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _sendReport(ChatMessage message, String reason) async {
    final colors = SpaceColors.of(context);
    try {
      await widget.api.reportMessage(message.id, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Thanks, report submitted', style: SpaceTypography.bodyMedium(color: colors.primaryText)),
          backgroundColor: colors.surface2,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not submit report', style: SpaceTypography.bodyMedium(color: colors.primaryText)),
          backgroundColor: colors.surface2,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.onBack != null) {
          widget.onBack!();
        }
      },
      child: SpaceScaffold(
        child: Column(
          children: [
            // Top Header: Globe (Left) • Space Name & Alias (Center) • Actions (Right)
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: colors.outline),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: widget.isDark ? 0.35 : 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      if (widget.onBack != null)
                        InkWell(
                          onTap: widget.onBack,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: colors.surface2,
                              shape: BoxShape.circle,
                              border: Border.all(color: colors.outline),
                            ),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              color: colors.primaryText,
                              size: 18,
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: widget.isDark ? const Color(0xFF1A2029) : colors.surface2,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.outline),
                          ),
                          child: Icon(
                            Icons.public_rounded,
                            color: widget.isDark ? const Color(0xFFAFC5FF) : colors.accent,
                            size: 19,
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.space.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SpaceTypography.headingSmall(
                                      color: colors.primaryText,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: colors.tertiary,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: colors.tertiary.withValues(alpha: 0.6),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Alias: ${widget.anonymousName}',
                              style: SpaceTypography.technical(
                                color: colors.tertiary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.onToggleTheme != null)
                        IconButton(
                          onPressed: widget.onToggleTheme,
                          icon: Icon(
                            widget.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            color: colors.secondaryText,
                            size: 20,
                          ),
                          tooltip: widget.isDark ? 'Light mode' : 'Dark mode',
                        ),
                      IconButton(
                        onPressed: widget.onLeave,
                        icon: Icon(
                          Icons.exit_to_app_rounded,
                          color: colors.danger,
                          size: 20,
                        ),
                        tooltip: 'Leave Space',
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Message Timeline
            Expanded(
              child: _loadingMessages
                  ? Center(child: CircularProgressIndicator(color: colors.accent))
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: colors.surface2,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: colors.outline),
                                ),
                                child: Icon(
                                  Icons.forum_outlined,
                                  size: 28,
                                  color: colors.secondaryAccent,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No messages yet',
                                style: SpaceTypography.headingSmall(color: colors.primaryText),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Start the conversation in this Space',
                                style: SpaceTypography.bodySmall(color: colors.secondaryText),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: _messages.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: colors.surface2,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: colors.outline),
                                    ),
                                    child: Text(
                                      'Today, ${TimeOfDay.now().format(context)}',
                                      style: SpaceTypography.technical(
                                        color: colors.secondaryText,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                            final message = _messages[index - 1];
                            final isMe = message.name == widget.anonymousName;
                            return MessageCard(
                              message: message,
                              isMe: isMe,
                              onLongPress: () => _showMessageActions(message),
                            );
                          },
                        ),
            ),
            ChatComposer(
              controller: _controller,
              spaceName: widget.space.name,
              onSend: _sendMessage,
              replyingTo: _replyingTo,
              onCancelReply: () => setState(() => _replyingTo = null),
            ),
          ],
        ),
      ),
    );
  }
}

// API-backed discovery screen
class SpaceDiscoveryScreen extends StatefulWidget {
  const SpaceDiscoveryScreen({
    super.key,
    required this.api,
    required this.latitude,
    required this.longitude,
    required this.onJoinSpace,
    required this.onCreateSpace,
    required this.onChangeLocation,
    required this.onLogout,
    this.onToggleTheme,
    this.isDark = true,
  });

  final ApiService api;
  final double latitude;
  final double longitude;
  final Future<bool> Function(Space) onJoinSpace;
  final VoidCallback onCreateSpace;
  final VoidCallback onChangeLocation;
  final VoidCallback onLogout;
  final VoidCallback? onToggleTheme;
  final bool isDark;

  @override
  State<SpaceDiscoveryScreen> createState() => _SpaceDiscoveryScreenState();
}

class _SpaceDiscoveryScreenState extends State<SpaceDiscoveryScreen> {
  List<SpaceData> _spaces = [];
  bool _loading = true;
  String? _error;
  String? _joiningId;

  @override
  void initState() {
    super.initState();
    _discover();
  }

  Future<void> _discover() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final spaces = await widget.api.discoverSpaces(
        widget.latitude,
        widget.longitude,
      );
      if (!mounted) return;
      setState(() {
        _spaces = spaces;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Space _toSpace(SpaceData data) => Space(
        id: data.id,
        name: data.name,
        visibility: data.visibility,
        latitude: data.latitude,
        longitude: data.longitude,
        radiusMeters: data.radiusMeters,
        createdAt: DateTime.now(),
      );

  Future<void> _join(SpaceData data) async {
    if (_joiningId != null) return;
    setState(() => _joiningId = data.id);
    final ok = await widget.onJoinSpace(_toSpace(data));
    if (mounted) setState(() => _joiningId = null);
    if (ok && mounted) _discover();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good Morning,';
    } else if (hour >= 12 && hour < 17) {
      return 'Good Afternoon,';
    } else if (hour >= 17 && hour < 21) {
      return 'Good Evening,';
    } else {
      return 'Good Night,';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SpaceScaffold(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header Bar: Globe (Left) • Space (Center) • Actions (Right)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  InkWell(
                    onTap: widget.onChangeLocation,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colors.surface2,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.outline),
                      ),
                      child: Icon(
                        Icons.public_rounded,
                        color: isDark ? const Color(0xFFAFC5FF) : colors.accent,
                        size: 21,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Space',
                      textAlign: TextAlign.center,
                      style: SpaceTypography.headingLarge(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onToggleTheme != null)
                        InkWell(
                          onTap: widget.onToggleTheme,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: colors.surface2,
                              shape: BoxShape.circle,
                              border: Border.all(color: colors.outline),
                            ),
                            child: Icon(
                              widget.isDark
                                  ? Icons.light_mode_rounded
                                  : Icons.dark_mode_rounded,
                              color: colors.secondaryText,
                              size: 19,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _discover,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: colors.surface2,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.outline),
                          ),
                          child: Icon(
                            Icons.refresh_rounded,
                            color: colors.secondaryText,
                            size: 19,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Greeting & Technical Location Badge
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting,
                    style: SpaceTypography.headingMedium(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w600,
                      fontSize: 24,
                    ),
                  ),
                  Text(
                    'Explorer.',
                    style: SpaceTypography.headingLarge(
                      color: isDark ? const Color(0xFFAFC5FF) : colors.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Location Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: colors.surface2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: colors.outline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: colors.accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: colors.accent.withValues(alpha: 0.6),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'SECTOR 76 • ${widget.latitude.toStringAsFixed(4)}° N, ${widget.longitude.toStringAsFixed(4)}° W',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SpaceTypography.technical(
                              color: colors.secondaryText,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Section Title: Nearby Spaces
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Row(
                children: [
                  Text(
                    'Nearby Spaces',
                    style: SpaceTypography.headingSmall(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!_loading && _spaces.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_spaces.length} ACTIVE',
                        style: SpaceTypography.technical(
                          color: colors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Icon(
                    Icons.radar_rounded,
                    size: 18,
                    color: colors.secondaryText,
                  ),
                ],
              ),
            ),

            // Spaces List / Loading / Error / Empty States
            if (_loading)
              Expanded(
                child: Center(
                    child: CircularProgressIndicator(color: colors.accent)),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            size: 44, color: colors.danger),
                        const SizedBox(height: 14),
                        Text(
                          'Unable to load nearby spaces',
                          style: SpaceTypography.headingSmall(
                              color: colors.primaryText),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Please check your connection and try again.',
                          textAlign: TextAlign.center,
                          style: SpaceTypography.bodyMedium(
                              color: colors.secondaryText),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _discover,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: colors.onAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_spaces.isEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: colors.surface2,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: colors.outline),
                                  ),
                                  child: Icon(
                                    Icons.near_me_outlined,
                                    size: 32,
                                    color: colors.disabled,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'No spaces nearby',
                                  style: SpaceTypography.headingSmall(
                                    color: colors.primaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "We couldn't find spaces around your current location.",
                                  textAlign: TextAlign.center,
                                  style: SpaceTypography.bodyMedium(
                                      color: colors.secondaryText),
                                ),
                                const SizedBox(height: 18),
                                OutlinedButton.icon(
                                  onPressed: widget.onChangeLocation,
                                  icon: Icon(Icons.edit_location_alt_rounded,
                                      size: 16, color: colors.secondaryText),
                                  label: Text('Change Location',
                                      style: SpaceTypography.bodyMedium(
                                          color: colors.primaryText,
                                          fontWeight: FontWeight.w600)),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: colors.outline),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _SpaceButton(
                          label: 'Create a Space',
                          icon: Icons.add_rounded,
                          onPressed: widget.onCreateSpace,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Stack(
                  children: [
                    ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                      itemCount: _spaces.length,
                      itemBuilder: (context, index) {
                        final space = _spaces[index];
                        return _SpaceCard(
                          name: space.name,
                          description: space.description,
                          distance: space.distanceMeters,
                          memberCount: space.memberCount,
                          joined: space.joined,
                          loading: _joiningId == space.id,
                          onTap: _joiningId == null ? () => _join(space) : null,
                        );
                      },
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 18,
                      child: _SpaceButton(
                        label: 'Create a Space',
                        icon: Icons.add_rounded,
                        onPressed: widget.onCreateSpace,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// API-backed My Spaces screen
class MySpacesScreen extends StatefulWidget {
  const MySpacesScreen({
    super.key,
    required this.api,
    required this.onOpenSpace,
    this.onToggleTheme,
    this.isDark = true,
  });

  final ApiService api;
  final Future<bool> Function(Space) onOpenSpace;
  final VoidCallback? onToggleTheme;
  final bool isDark;

  @override
  State<MySpacesScreen> createState() => _MySpacesScreenState();
}

class _MySpacesScreenState extends State<MySpacesScreen> {
  List<SpaceData> _spaces = [];
  bool _loading = true;
  String? _error;
  String? _openingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final spaces = await widget.api.joinedSpaces();
      if (!mounted) return;
      setState(() {
        _spaces = spaces;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Space _toSpace(SpaceData data) => Space(
        id: data.id,
        name: data.name,
        visibility: data.visibility,
        latitude: data.latitude,
        longitude: data.longitude,
        radiusMeters: data.radiusMeters,
        createdAt: DateTime.now(),
      );

  Future<void> _open(SpaceData data) async {
    if (_openingId != null) return;
    setState(() => _openingId = data.id);
    final ok = await widget.onOpenSpace(_toSpace(data));
    if (mounted) setState(() => _openingId = null);
    if (ok && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return SpaceScaffold(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Spaces',
                          style: SpaceTypography.headingLarge(
                              color: colors.primaryText),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Spaces you are in',
                          style: SpaceTypography.bodyMedium(
                              color: colors.secondaryText),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onToggleTheme != null)
                    IconButton(
                      onPressed: widget.onToggleTheme,
                      icon: Icon(
                        widget.isDark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        color: colors.secondaryText,
                        size: 20,
                      ),
                      tooltip: widget.isDark ? 'Light mode' : 'Dark mode',
                    ),
                  IconButton(
                    onPressed: _load,
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: colors.secondaryText,
                      size: 20,
                    ),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
            if (_loading)
              Expanded(
                child: Center(
                    child: CircularProgressIndicator(color: colors.accent)),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            style: SpaceTypography.bodyMedium(
                                color: colors.secondaryText)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_spaces.isEmpty)
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: colors.surface2,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.outline),
                          ),
                          child: Icon(Icons.forum_outlined,
                              size: 28, color: colors.disabled),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'You are not in any Spaces',
                          style: SpaceTypography.headingSmall(
                              color: colors.primaryText),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Join one from the Discover tab',
                          style: SpaceTypography.bodyMedium(
                              color: colors.disabled),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  itemCount: _spaces.length,
                  itemBuilder: (context, index) {
                    final space = _spaces[index];
                    return _SpaceCard(
                      name: space.name,
                      description: space.description,
                      distance: space.distanceMeters,
                      memberCount: space.memberCount,
                      joined: true,
                      loading: _openingId == space.id,
                      onTap: _openingId == null ? () => _open(space) : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Reusable widgets
class _SpaceButton extends StatelessWidget {
  const _SpaceButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          textStyle: SpaceTypography.headingSmall(
            color: colors.onAccent,
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({
    required this.name,
    this.description,
    this.distance = 0,
    this.memberCount = 0,
    this.joined = false,
    this.loading = false,
    this.onTap,
  });

  final String name;
  final String? description;
  final double distance;
  final int memberCount;
  final bool joined;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: joined
                  ? colors.tertiary.withValues(alpha: 0.35)
                  : colors.outline,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Category / Space Icon + Distance Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A2029) : colors.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.outline),
                    ),
                    child: Icon(
                      joined ? Icons.forum_rounded : Icons.radar_rounded,
                      color: joined
                          ? colors.tertiary
                          : (isDark
                              ? const Color(0xFFAFC5FF)
                              : colors.accent),
                      size: 20,
                    ),
                  ),
                  if (distance > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color:
                            isDark ? const Color(0xFF151A21) : colors.surface2,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: colors.outline),
                      ),
                      child: Text(
                        '${distance.toStringAsFixed(0)}m',
                        style: SpaceTypography.technical(
                          color: isDark
                              ? const Color(0xFFAFC5FF)
                              : colors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Space Name
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SpaceTypography.headingSmall(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                ),
              ),
              const SizedBox(height: 4),

              // Space Description
              if (description != null && description!.trim().isNotEmpty) ...[
                Text(
                  description!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SpaceTypography.bodyMedium(
                    color: colors.secondaryText,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
              ] else
                const SizedBox(height: 6),

              // Activity & Active Members Row
              Row(
                children: [
                  // Overlapping avatar dots indicator
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AvatarDot(color: colors.accent),
                      Transform.translate(
                        offset: const Offset(-4, 0),
                        child: _AvatarDot(color: colors.secondaryAccent),
                      ),
                      Transform.translate(
                        offset: const Offset(-8, 0),
                        child: _AvatarDot(color: colors.tertiary),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.tertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    memberCount > 0 ? '$memberCount Active' : 'Active',
                    style: SpaceTypography.technical(
                      color: colors.secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Action Button: JOIN SEQUENCE / ENTER SPACE / JOINED
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: joined
                        ? colors.tertiary.withValues(alpha: 0.12)
                        : (isDark ? Colors.transparent : colors.surface2),
                    foregroundColor: joined
                        ? colors.tertiary
                        : (isDark
                            ? const Color(0xFFAFC5FF)
                            : colors.accent),
                    side: BorderSide(
                      color: joined
                          ? colors.tertiary.withValues(alpha: 0.5)
                          : colors.accent,
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: loading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.accent,
                          ),
                        )
                      : Text(
                          joined ? 'JOINED' : 'JOIN SEQUENCE',
                          style: SpaceTypography.technical(
                            color: joined
                                ? colors.tertiary
                                : (isDark
                                    ? const Color(0xFFAFC5FF)
                                    : colors.accent),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarDot extends StatelessWidget {
  const _AvatarDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).scaffoldBackgroundColor,
          width: 1.5,
        ),
      ),
    );
  }
}

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.spaceName = 'Space',
    this.replyingTo,
    this.onCancelReply,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final String spaceName;
  final ChatMessage? replyingTo;
  final VoidCallback? onCancelReply;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.outline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyingTo != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.outlineSubtle),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 18,
                        decoration: BoxDecoration(
                          color: colors.secondaryAccent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Replying to ${replyingTo!.name}: ${replyingTo!.text}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SpaceTypography.bodySmall(color: colors.secondaryText),
                        ),
                      ),
                      if (onCancelReply != null)
                        GestureDetector(
                          onTap: onCancelReply,
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: colors.disabled,
                          ),
                        ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A2029) : colors.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.outline),
                    ),
                    child: Icon(
                      Icons.radar_rounded,
                      color: isDark ? const Color(0xFFAFC5FF) : colors.accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      style: SpaceTypography.bodyMedium(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Message $spaceName anonymously...',
                        hintStyle: SpaceTypography.bodyMedium(color: colors.disabled),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onSend,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colors.accent.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: colors.onAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MessageCard extends StatelessWidget {
  const MessageCard({
    super.key,
    required this.message,
    this.isMe = false,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool isMe;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Sender Name (For incoming messages)
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 4),
                  child: Text(
                    message.name,
                    style: SpaceTypography.technical(
                      color: isDark ? const Color(0xFFAFC5FF) : colors.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

              // Message Bubble
              GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 15, vertical: 11),
                  decoration: BoxDecoration(
                    color: isMe
                        ? (isDark
                            ? const Color(0xFF101A2A)
                            : const Color(0xFFEEF4FF))
                        : (isDark ? colors.surface : colors.surface),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: isMe
                          ? const Radius.circular(18)
                          : const Radius.circular(4),
                      bottomRight: isMe
                          ? const Radius.circular(4)
                          : const Radius.circular(18),
                    ),
                    border: Border.all(
                      color: isMe
                          ? colors.accent
                          : colors.outline,
                      width: isMe ? 1.2 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.25 : 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      // Quoted Reply Preview
                      if (message.replyText != null) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF080D14)
                                : colors.surface2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border(
                              left: BorderSide(
                                color: isMe
                                    ? colors.accent
                                    : colors.secondaryAccent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.reply_rounded,
                                  size: 13, color: colors.secondaryText),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${message.replyText}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: SpaceTypography.bodySmall(
                                    color: colors.secondaryText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Message Content Text
                      Text(
                        message.text,
                        style: SpaceTypography.bodyLarge(
                          color: isMe
                              ? (isDark
                                  ? const Color(0xFFAFC5FF)
                                  : const Color(0xFF1E3A8A))
                              : (isDark
                                  ? const Color(0xFFD8DEE9)
                                  : colors.primaryText),
                          fontSize: 14.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Reactions
              if (message.reactions.isNotEmpty) ...[
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final entry in message.reactions.entries)
                      if (entry.value > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colors.surface2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.outline),
                          ),
                          child: Text(
                            '${entry.key} ${entry.value}',
                            style: SpaceTypography.technical(
                              color: colors.primaryText,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class StepCard extends StatelessWidget {
  const StepCard({
    super.key,
    required this.step,
    required this.title,
    required this.child,
  });

  final String step;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step,
            style: SpaceTypography.technical(color: colors.secondaryAccent, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: SpaceTypography.headingSmall(color: colors.primaryText),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class SpaceTextField extends StatelessWidget {
  const SpaceTextField({super.key, required this.controller, this.hintText});

  final TextEditingController controller;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return TextField(
      controller: controller,
      style: SpaceTypography.bodyLarge(color: colors.primaryText, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: SpaceTypography.bodyMedium(color: colors.disabled),
        filled: true,
        fillColor: colors.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: colors.outline),
          borderRadius: BorderRadius.circular(16),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.outline),
          borderRadius: BorderRadius.circular(16),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.accent, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? colors.accent.withValues(alpha: 0.15) : colors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colors.accent : colors.outline,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StatusDot(
              color: selected ? colors.accent : colors.disabled,
              hollow: !selected,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: SpaceTypography.bodyMedium(
                color: selected ? colors.primaryText : colors.secondaryText,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GeofenceDecisionPanel extends StatelessWidget {
  const GeofenceDecisionPanel({super.key, required this.validation});

  final GeofenceValidationResult validation;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final color = switch (validation.decision) {
      GeofenceDecision.inside => colors.tertiary,
      GeofenceDecision.nearBoundary => colors.warning,
      GeofenceDecision.outside => colors.dangerStrong,
      GeofenceDecision.lowAccuracy => colors.warning,
      GeofenceDecision.rejected => colors.dangerStrong,
    };
    final label = switch (validation.decision) {
      GeofenceDecision.inside => 'Inside perimeter',
      GeofenceDecision.nearBoundary => 'Near boundary',
      GeofenceDecision.outside => 'Outside perimeter',
      GeofenceDecision.lowAccuracy => 'Low accuracy',
      GeofenceDecision.rejected => 'Rejected',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(Icons.radar_rounded, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: SpaceTypography.bodyMedium(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${validation.distanceMeters.toStringAsFixed(1)}m from center',
                  style: SpaceTypography.technical(
                    color: colors.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SpaceButton extends StatelessWidget {
  const SpaceButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return FilledButton.icon(
      onPressed: onPressed,
      icon: loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.onAccent,
              ),
            )
          : Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        textStyle: SpaceTypography.headingSmall(
          color: colors.onAccent,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
    );
  }
}

class SpaceScaffold extends StatelessWidget {
  const SpaceScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.3,
            colors: [colors.gradientTop, colors.gradientBottom],
            stops: const [0, 0.65],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: child,
        ),
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.hollow = false});

  final Color color;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: hollow ? Colors.transparent : color,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.6),
      ),
    );
  }
}

class Space {
  Space({
    required this.id,
    required this.name,
    required this.visibility,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String visibility;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final DateTime createdAt;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.name,
    required this.text,
    required this.color,
    required this.reactions,
    this.replyTo,
    this.replyText,
  });

  final String id;
  final String name;
  final String text;
  final Color color;
  final String? replyTo;
  final String? replyText;
  final Map<String, int> reactions;
}

const _reactionEmojis = ['👍', '❤️', '😄', '😂', '🔥', '🎉'];

const _reportReasons = [
  'Spam',
  'Harassment',
  'Hate speech',
  'Inappropriate content',
  'Other',
];

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outline),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 19)),
      ),
    );
  }
}
