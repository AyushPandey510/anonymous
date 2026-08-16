import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:space_mobile/features/location/data/location_service.dart';
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
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
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
  const AppLoader({
    super.key,
    required this.onToggleTheme,
    required this.isDark,
  });

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
                Icon(Icons.cloud_off_rounded, size: 48, color: colors.disabled),
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: colors.secondaryText)),
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
      return const OrbitOpeningScreen();
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
    _loadSavedLocation();
  }

  @override
  void dispose() {
    _geofenceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedLocation() async {
    final saved = await LocationSelectionScreen.getSavedLocation();
    if (!mounted) return;
    if (saved != null) {
      setState(() => _userLocation = saved);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
        initialLocation: _userLocation,
        onLocationSelected: _onLocationSelected,
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
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: colors.navBackground,
              border: Border(top: BorderSide(color: colors.outline)),
              boxShadow: [
                BoxShadow(
                  color: colors.accent.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _screen = index == 0
                      ? AppScreen.discovery
                      : AppScreen.mySpaces;
                });
              },
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              indicatorColor: colors.accent.withValues(alpha: 0.20),
              height: 76,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                NavigationDestination(
                  icon: Icon(
                    Icons.explore_outlined,
                    color: colors.secondaryText,
                    size: 23,
                  ),
                  selectedIcon: Icon(
                    Icons.explore_rounded,
                    color: colors.accent,
                    size: 23,
                  ),
                  label: 'Discovery',
                ),
                NavigationDestination(
                  icon: Icon(
                    Icons.layers_outlined,
                    color: colors.secondaryText,
                    size: 23,
                  ),
                  selectedIcon: Icon(
                    Icons.layers_rounded,
                    color: colors.accent,
                    size: 23,
                  ),
                  label: 'My Spaces',
                ),
              ],
            ),
          ),
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
  final _locationService = const SpaceLocationService();
  final _validator = const GeofenceValidator();
  bool _isPrivate = false;
  double _radius = 120;
  late GeoPoint _selectedPoint;
  double _accuracy = 18;
  bool _locating = true;
  bool _hasDeviceFix = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialLocation;
    _refreshDeviceLocation();
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
      accuracyMeters: _accuracy,
      capturedAt: DateTime.now().toUtc(),
    );
    final validation = _validator.validate(
      geofence: geofence,
      current: currentFix,
    );

    return SpaceScaffold(
      child: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 118),
              children: [
                Row(
                  children: [
                    _GlassIconButton(
                      icon: Icons.close_rounded,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Create Space',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: colors.accent,
                        ),
                      ),
                    ),
                    if (widget.onToggleTheme != null)
                      _GlassIconButton(
                        icon: widget.isDark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        onPressed: widget.onToggleTheme,
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 34),
                StepCard(
                  step: '1. Identity',
                  title: 'Space Name',
                  child: SpaceTextField(controller: _nameController),
                ),
                const SizedBox(height: 18),
                StepCard(
                  step: 'Visibility',
                  title: 'Access Mode',
                  child: Row(
                    children: [
                      Expanded(
                        child: ChoicePill(
                          label: 'Public',
                          selected: !_isPrivate,
                          icon: Icons.public_rounded,
                          onTap: () => setState(() => _isPrivate = false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ChoicePill(
                          label: 'Invite Only',
                          selected: _isPrivate,
                          icon: Icons.lock_rounded,
                          onTap: () => setState(() => _isPrivate = true),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 34),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '2. Geofence',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    GeofenceDecisionPanel(
                      validation: validation,
                      compact: true,
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
                const SizedBox(height: 14),
                _GlassPanel(
                  padding: EdgeInsets.zero,
                  borderRadius: 28,
                  child: Column(
                    children: [
                      InteractiveGeofenceMap(
                        point: _selectedPoint,
                        radiusMeters: _radius.round(),
                        validation: validation,
                        allowPointSelection: false,
                        showSearch: false,
                        onPointChanged: (point) {
                          setState(() => _selectedPoint = point);
                        },
                        onAccuracyChanged: (accuracy) {
                          _accuracy = accuracy;
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Radius',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                    color: colors.secondaryText,
                                  ),
                                ),
                                const Spacer(),
                                _GlassChip(
                                  icon: Icons.radio_button_checked_rounded,
                                  label: '${_radius.round()}m',
                                  accent: colors.accent,
                                ),
                              ],
                            ),
                            Slider(
                              value: _radius,
                              min: CircleGeofence.minRadiusMeters.toDouble(),
                              max: CircleGeofence.maxRadiusMeters.toDouble(),
                              divisions:
                                  CircleGeofence.maxRadiusMeters -
                                  CircleGeofence.minRadiusMeters,
                              activeColor: colors.accent,
                              inactiveColor: colors.outlineSubtle,
                              onChanged: (value) =>
                                  setState(() => _radius = value),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${CircleGeofence.minRadiusMeters}m',
                                  style: TextStyle(
                                    color: colors.disabled,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '${CircleGeofence.maxRadiusMeters}m',
                                  style: TextStyle(
                                    color: colors.disabled,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: SpaceButton(
                label: _creating
                    ? 'Creating...'
                    : _locating
                    ? 'Detecting Location...'
                    : 'Initialize Space',
                icon: Icons.rocket_launch_rounded,
                loading: _creating || _locating,
                onPressed: _creating || _locating || !_hasDeviceFix
                    ? null
                    : _createSpace,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshDeviceLocation() async {
    setState(() => _locating = true);
    try {
      final fix = await _locationService.currentFix();
      if (!mounted) return;
      setState(() {
        _selectedPoint = fix.point;
        _accuracy = fix.accuracyMeters ?? 75;
        _hasDeviceFix = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasDeviceFix = false);
      final colors = SpaceColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not detect current location. Enable location and try again.',
            style: TextStyle(color: colors.primaryText),
          ),
          backgroundColor: colors.card,
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _createSpace() async {
    setState(() => _creating = true);
    try {
      final fix = await _locationService.currentFix();
      if (!mounted) return;
      setState(() {
        _selectedPoint = fix.point;
        _accuracy = fix.accuracyMeters ?? 75;
        _hasDeviceFix = true;
      });
      final response = await widget.api.createSpace(
        name: _nameController.text.trim().isEmpty
            ? 'Untitled Space'
            : _nameController.text.trim(),
        visibility: _isPrivate ? 'private' : 'public',
        latitude: fix.point.latitude,
        longitude: fix.point.longitude,
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
          content: Text(
            'Failed to create: ${e.toString()}',
            style: TextStyle(color: colors.primaryText),
          ),
          backgroundColor: colors.card,
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
    _socket =
        widget.socket ??
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
      _messages.add(
        ChatMessage(
          id: message.id,
          name: message.anonymousId,
          text: message.content,
          replyTo: message.replyTo,
          replyText: message.replyContent,
          createdAt: DateTime.tryParse(message.createdAt),
          color: colors.accent,
          reactions: message.reactions.fold<Map<String, int>>(
            {},
            (map, r) => map..[r.emoji] = r.count,
          ),
        ),
      );
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
            _messages.add(
              ChatMessage(
                id: m.id,
                name: m.anonymousId,
                text: m.content,
                replyTo: m.replyTo,
                replyText: m.replyContent,
                createdAt: DateTime.tryParse(m.createdAt),
                color: colors.accent,
                reactions: m.reactions.fold<Map<String, int>>(
                  {},
                  (map, r) => map..[r.emoji] = r.count,
                ),
              ),
            );
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
                Text(
                  message.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.secondaryText, fontSize: 13),
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
                  leading: Icon(
                    Icons.reply_rounded,
                    color: colors.secondaryText,
                  ),
                  title: Text(
                    'Reply',
                    style: TextStyle(color: colors.primaryText),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startReply(message);
                  },
                ),
                if (message.name == widget.anonymousName)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: colors.danger,
                    ),
                    title: Text(
                      'Delete',
                      style: TextStyle(color: colors.danger),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _confirmDelete(message);
                    },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.flag_outlined,
                    color: colors.secondaryText,
                  ),
                  title: Text(
                    'Report',
                    style: TextStyle(color: colors.primaryText),
                  ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Delete message?',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
        content: Text(
          'This removes the message for everyone. Available within 15 minutes of sending.',
          style: SpaceTypography.bodyMedium(color: colors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: colors.secondaryText),
            ),
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
          content: Text(
            'Message deleted',
            style: TextStyle(color: colors.primaryText),
          ),
          backgroundColor: colors.card,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final messageText = e.statusCode == 403
          ? 'Only your own messages can be deleted'
          : 'Could not delete message';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            messageText,
            style: TextStyle(color: colors.primaryText),
          ),
          backgroundColor: colors.card,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Report message',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
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
          content: Text(
            'Thanks, report submitted',
            style: TextStyle(color: colors.primaryText),
          ),
          backgroundColor: colors.card,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not submit report',
            style: TextStyle(color: colors.primaryText),
          ),
          backgroundColor: colors.card,
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
                child: _GlassPanel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  borderRadius: 24,
                  child: Row(
                    children: [
                      if (widget.onBack != null)
                        _GlassIconButton(
                          icon: Icons.arrow_back_rounded,
                          onPressed: widget.onBack,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Space',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: colors.accent,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.space.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.secondaryText,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                StatusDot(color: colors.accent),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    widget.anonymousName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.disabled,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
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
                        _GlassIconButton(
                          icon: widget.isDark
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                          onPressed: widget.onToggleTheme,
                        ),
                      _GlassIconButton(
                        icon: Icons.more_vert_rounded,
                        onPressed: widget.onLeave,
                        foregroundColor: colors.danger,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loadingMessages
                  ? Center(
                      child: CircularProgressIndicator(color: colors.accent),
                    )
                  : _messages.isEmpty
                  ? _EmptyState(
                      icon: Icons.forum_outlined,
                      title: 'No messages yet',
                      subtitle: 'Start the conversation',
                      actionLabel: null,
                      onAction: null,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                      itemCount: _messages.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: _GlassChip(
                                icon: Icons.today_rounded,
                                label: 'Today',
                                accent: colors.secondaryText,
                              ),
                            ),
                          );
                        }
                        final message = _messages[index - 1];
                        return MessageCard(
                          message: message,
                          isMine: message.name == widget.anonymousName,
                          onLongPress: () => _showMessageActions(message),
                        );
                      },
                    ),
            ),
            ChatComposer(
              controller: _controller,
              onSend: _sendMessage,
              replyingTo: _replyingTo,
              spaceName: widget.space.name,
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
            _SpaceTopBar(
              centerTitle: 'Space',
              leadingIcon: Icons.language_rounded,
              onLeading: widget.onChangeLocation,
              trailingIcon: widget.isDark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              onTrailing: widget.onToggleTheme,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: '$_greeting,\n',
                      children: [
                        TextSpan(
                          text: 'Explorer.',
                          style: TextStyle(color: colors.accent),
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 32,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _GlassChip(
                    icon: Icons.my_location_rounded,
                    label:
                        '${widget.latitude.toStringAsFixed(4)}, ${widget.longitude.toStringAsFixed(4)}',
                    accent: colors.accent,
                  ),
                ],
              ),
            ),

            // Spaces List / Loading / Error / Empty States
            if (_loading)
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: colors.accent),
                ),
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
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: colors.danger,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Unable to load nearby spaces',
                          style: SpaceTypography.headingSmall(
                              color: colors.primaryText),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Please check your connection and try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.secondaryText,
                            fontSize: 14,
                          ),
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
                child: Stack(
                  children: [
                    _EmptyState(
                      icon: Icons.radar_rounded,
                      title: 'No spaces nearby',
                      subtitle:
                          "We couldn't find spaces around your current location.",
                      actionLabel: 'Change Location',
                      onAction: widget.onChangeLocation,
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 20,
                      child: _SpaceButton(
                        label: 'Create a Space',
                        icon: Icons.add_rounded,
                        onPressed: widget.onCreateSpace,
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 920
                            ? 3
                            : constraints.maxWidth >= 620
                            ? 2
                            : 1;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 112),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 18,
                                mainAxisSpacing: 18,
                                childAspectRatio: columns == 1 ? 1.06 : 0.88,
                              ),
                          itemCount: _spaces.length,
                          itemBuilder: (context, index) {
                            final space = _spaces[index];
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(
                                milliseconds: 220 + (index * 45).clamp(0, 320),
                              ),
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, (1 - value) * 14),
                                    child: child,
                                  ),
                                );
                              },
                              child: _SpaceCard(
                                name: space.name,
                                description: space.description,
                                distance: space.distanceMeters,
                                memberCount: space.memberCount,
                                joined: space.joined,
                                loading: _joiningId == space.id,
                                onTap: _joiningId == null
                                    ? () => _join(space)
                                    : null,
                              ),
                            );
                          },
                        );
                      },
                    ),
                    Positioned(
                      right: 24,
                      bottom: 22,
                      child: _GradientFab(
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
            _SpaceTopBar(
              centerTitle: 'Space',
              leadingIcon: Icons.refresh_rounded,
              onLeading: _load,
              trailingIcon: widget.isDark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              onTrailing: widget.onToggleTheme,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Spaces',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 32,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _GlassChip(
                    icon: Icons.layers_rounded,
                    label: '${_spaces.length} active memberships',
                    accent: colors.accent,
                  ),
                ],
              ),
            ),
            if (_loading)
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: colors.accent),
                ),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(color: colors.secondaryText),
                        ),
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
                child: _EmptyState(
                  icon: Icons.layers_outlined,
                  title: 'You are not in any Spaces',
                  subtitle: 'Join one from the Discovery tab',
                  actionLabel: null,
                  onAction: null,
                ),
              )
            else
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 920
                        ? 3
                        : constraints.maxWidth >= 620
                        ? 2
                        : 1;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 112),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 18,
                        mainAxisSpacing: 18,
                        childAspectRatio: columns == 1 ? 1.06 : 0.88,
                      ),
                      itemCount: _spaces.length,
                      itemBuilder: (context, index) {
                        final space = _spaces[index];
                        return _SpaceCard(
                          name: space.name,
                          description: space.description,
                          memberCount: space.memberCount,
                          joined: true,
                          loading: _openingId == space.id,
                          onTap: _openingId == null ? () => _open(space) : null,
                        );
                      },
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
class _SpaceTopBar extends StatelessWidget {
  const _SpaceTopBar({
    required this.centerTitle,
    required this.leadingIcon,
    required this.onLeading,
    required this.trailingIcon,
    required this.onTrailing,
  });

  final String centerTitle;
  final IconData leadingIcon;
  final VoidCallback? onLeading;
  final IconData trailingIcon;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.58),
            border: Border(bottom: BorderSide(color: colors.outline)),
          ),
          child: Row(
            children: [
              _GlassIconButton(icon: leadingIcon, onPressed: onLeading),
              Expanded(
                child: Text(
                  centerTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 31,
                    fontWeight: FontWeight.w800,
                    color: colors.accent,
                  ),
                ),
              ),
              _GlassIconButton(icon: trailingIcon, onPressed: onTrailing),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isDark
                ? colors.card.withValues(alpha: 0.62)
                : Colors.white.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.82),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onPressed,
    this.foregroundColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: colors.chipBackground,
          disabledBackgroundColor: colors.chipBackground,
          foregroundColor: foregroundColor ?? colors.accent,
          disabledForegroundColor: colors.disabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: colors.outline),
          ),
        ),
        icon: Icon(icon, size: 21),
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.label, required this.accent, this.icon});

  final String label;
  final Color accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientFab extends StatelessWidget {
  const _GradientFab({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.36),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(icon, color: colors.onAccent, size: 31),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GlassPanel(
              borderRadius: 999,
              padding: const EdgeInsets.all(22),
              child: Icon(icon, size: 42, color: colors.accent),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Montserrat',
                color: colors.primaryText,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: Icon(
                  Icons.edit_location_alt_rounded,
                  size: 16,
                  color: colors.accent,
                ),
                label: Text(
                  actionLabel!,
                  style: TextStyle(
                    color: colors.primaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [colors.accent, const Color(0xFFD0BCFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: const Color(0xFF001A42)),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF001A42),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
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
    final icon = joined ? Icons.forum_rounded : _spaceIcon(name);
    final activeColor = joined ? const Color(0xFFD0BCFF) : colors.accent;
    final body = description?.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: _GlassPanel(
          borderRadius: 28,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          activeColor.withValues(alpha: 0.92),
                          const Color(0xFF8B5CF6).withValues(alpha: 0.82),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.24),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Icon(icon, color: colors.onAccent, size: 24),
                  ),
                  const Spacer(),
                  if (loading)
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.accent,
                      ),
                    )
                  else
                    _GlassChip(
                      icon: joined
                          ? Icons.check_circle_rounded
                          : Icons.radar_rounded,
                      label: joined ? 'Joined' : _formatDistance(distance),
                      accent: activeColor,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 21,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
              if (body != null && body.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
              const Spacer(),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (memberCount > 0)
                    _GlassChip(
                      icon: Icons.people_alt_rounded,
                      label: '$memberCount Active',
                      accent: colors.secondaryText,
                    ),
                  _GlassChip(
                    icon: Icons.public_rounded,
                    label: joined ? 'Open Channel' : 'Nearby',
                    accent: colors.secondaryText,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: activeColor.withValues(alpha: 0.72),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.14),
                      blurRadius: 16,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  joined ? 'Enter Space' : 'Join Sequence',
                  style: TextStyle(
                    color: activeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _spaceIcon(String seed) {
    final icons = [
      Icons.terminal_rounded,
      Icons.headphones_rounded,
      Icons.local_cafe_rounded,
      Icons.nightlife_rounded,
      Icons.restaurant_rounded,
      Icons.bolt_rounded,
      Icons.blur_on_rounded,
    ];
    return icons[seed.hashCode.abs() % icons.length];
  }

  String _formatDistance(double value) {
    if (value <= 0) return 'In Range';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}km';
    return '${value.toStringAsFixed(0)}m';
  }
}

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.replyingTo,
    this.spaceName,
    this.onCancelReply,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ChatMessage? replyingTo;
  final String? spaceName;
  final VoidCallback? onCancelReply;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyingTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _GlassPanel(
                    borderRadius: 18,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.reply_rounded,
                          size: 17,
                          color: colors.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Replying to ${replyingTo!.name}: '
                            '${replyingTo!.text}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.secondaryText,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (onCancelReply != null)
                          GestureDetector(
                            onTap: onCancelReply,
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: colors.disabled,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Container(
                color: colors.surface.withValues(alpha: 0.78),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Icon(
                        Icons.add_circle_rounded,
                        color: colors.secondaryText,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GlassPanel(
                        borderRadius: 28,
                        padding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: controller,
                                minLines: 1,
                                maxLines: 4,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: colors.primaryText,
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      'Message ${spaceName ?? 'Space'}...',
                                  hintStyle: TextStyle(color: colors.disabled),
                                  border: InputBorder.none,
                                ),
                                onSubmitted: (_) => onSend(),
                              ),
                            ),
                            Icon(
                              Icons.mood_rounded,
                              size: 21,
                              color: colors.disabled,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: onSend,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [colors.accent, const Color(0xFF8B5CF6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.accent.withValues(alpha: 0.24),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.send_rounded,
                          color: colors.onAccent,
                          size: 21,
                        ),
                      ),
                    ],
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

class MessageCard extends StatelessWidget {
  const MessageCard({
    super.key,
    required this.message,
    required this.isMine,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool isMine;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
      bottomLeft: Radius.circular(isMine ? 22 : 5),
      bottomRight: Radius.circular(isMine ? 5 : 22),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.82),
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!isMine)
                      Padding(
                        padding: const EdgeInsets.only(left: 10, bottom: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.name,
                              style: TextStyle(
                                color: colors.secondaryText,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (message.createdAt != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                _formatMessageTime(message.createdAt!),
                                style: TextStyle(
                                  color: colors.disabled,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: bubbleRadius,
                        gradient: isMine
                            ? const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isMine ? null : colors.card,
                        border: isMine
                            ? null
                            : Border.all(color: colors.outline),
                        boxShadow: [
                          BoxShadow(
                            color: (isMine ? colors.accent : Colors.black)
                                .withValues(alpha: isMine ? 0.16 : 0.05),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.replyText != null) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isMine
                                    ? Colors.white.withValues(alpha: 0.16)
                                    : colors.accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border(
                                  left: BorderSide(
                                    color: isMine
                                        ? Colors.white
                                        : colors.accent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Text(
                                '${message.replyText}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isMine
                                      ? Colors.white
                                      : colors.secondaryText,
                                  fontSize: 12,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                          Text(
                            message.text,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.38,
                              color: isMine ? Colors.white : colors.primaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (message.reactions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final entry in message.reactions.entries)
                            if (entry.value > 0)
                              _GlassChip(
                                label: '${entry.key} ${entry.value}',
                                accent: colors.accent,
                              ),
                        ],
                      ),
                    ],
                    if (isMine && message.createdAt != null) ...[
                      const SizedBox(height: 5),
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          _formatMessageTime(message.createdAt!),
                          style: TextStyle(
                            color: colors.disabled,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatMessageTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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
          Text(step, style: TextStyle(color: colors.disabled, fontSize: 12)),
          const SizedBox(height: 5),
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
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.14)
              : colors.chipBackground,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? colors.accent : colors.outline),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Icon(
                icon,
                size: 18,
                color: selected ? colors.accent : colors.secondaryText,
              )
            else
              StatusDot(
                color: selected ? colors.accent : colors.disabled,
                hollow: !selected,
              ),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? colors.accent : colors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GeofenceDecisionPanel extends StatelessWidget {
  const GeofenceDecisionPanel({
    super.key,
    required this.validation,
    this.compact = false,
  });

  final GeofenceValidationResult validation;
  final bool compact;

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

    if (compact) {
      return _GlassChip(icon: Icons.radar_rounded, label: label, accent: color);
    }

    return SizedBox(
      width: double.infinity,
      child: _GlassPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.radar_rounded, color: color, size: 20),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${validation.distanceMeters.toStringAsFixed(1)}m from center',
                    style: TextStyle(color: colors.secondaryText, fontSize: 12),
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

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [colors.accent, const Color(0xFFD0BCFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 56,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF001A42),
                    ),
                  )
                else
                  Icon(icon, size: 20, color: const Color(0xFF001A42)),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF001A42),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(color: colors.background),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.18,
                    colors: [
                      colors.gradientTop.withValues(alpha: isDark ? 0.92 : 0.7),
                      colors.gradientBottom,
                    ],
                    stops: const [0, 0.62],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.centerLeft,
                    radius: 1.08,
                    colors: [
                      colors.accent.withValues(alpha: isDark ? 0.07 : 0.10),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.48],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _StarfieldPainter(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : colors.accent.withValues(alpha: 0.10),
                ),
              ),
            ),
            Material(color: Colors.transparent, child: child),
          ],
        ),
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  const _StarfieldPainter({required this.color});

  final Color color;

  static const _stars = <Offset>[
    Offset(0.08, 0.10),
    Offset(0.18, 0.28),
    Offset(0.31, 0.16),
    Offset(0.43, 0.34),
    Offset(0.58, 0.12),
    Offset(0.72, 0.24),
    Offset(0.86, 0.10),
    Offset(0.92, 0.42),
    Offset(0.13, 0.58),
    Offset(0.37, 0.70),
    Offset(0.67, 0.62),
    Offset(0.82, 0.78),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final star in _stars) {
      canvas.drawCircle(
        Offset(star.dx * size.width, star.dy * size.height),
        1.1,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) {
    return oldDelegate.color != color;
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
    this.createdAt,
  });

  final String id;
  final String name;
  final String text;
  final Color color;
  final String? replyTo;
  final String? replyText;
  final DateTime? createdAt;
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
