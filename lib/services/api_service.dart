import 'api_client.dart';

class SpaceData {
  final String id;
  final String name;
  final String? description;
  final String visibility;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final double distanceMeters;
  final int memberCount;
  final bool joined;
  final String createdAt;

  SpaceData({
    required this.id,
    required this.name,
    this.description,
    required this.visibility,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.distanceMeters,
    this.memberCount = 0,
    this.joined = false,
    required this.createdAt,
  });

  factory SpaceData.fromJson(Map<String, dynamic> json) => SpaceData(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        visibility: json['visibility'] as String? ?? 'public',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        radiusMeters: json['radius_meters'] as int,
        distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? 0,
        memberCount: json['member_count'] as int? ?? 0,
        joined: json['joined'] as bool? ?? false,
        createdAt: json['created_at'] as String,
      );
}

class SessionData {
  final String id;
  final String spaceId;
  final String anonymousId;
  final String expiresAt;
  final String status;

  SessionData({
    required this.id,
    required this.spaceId,
    required this.anonymousId,
    required this.expiresAt,
    required this.status,
  });

  factory SessionData.fromJson(Map<String, dynamic> json) => SessionData(
        id: json['id'] as String,
        spaceId: json['space_id'] as String,
        anonymousId: json['anonymous_id'] as String,
        expiresAt: json['expires_at'] as String,
        status: json['status'] as String? ?? 'active',
      );
}

class ReactionData {
  final String emoji;
  final int count;

  ReactionData({required this.emoji, required this.count});

  factory ReactionData.fromJson(Map<String, dynamic> json) => ReactionData(
        emoji: json['emoji'] as String,
        count: json['count'] as int,
      );
}

class MessageData {
  final String id;
  final String anonymousId;
  final String content;
  final String? replyTo;
  final String? replyContent;
  final String createdAt;
  final List<ReactionData> reactions;

  MessageData({
    required this.id,
    required this.anonymousId,
    required this.content,
    this.replyTo,
    this.replyContent,
    required this.createdAt,
    this.reactions = const [],
  });

  factory MessageData.fromJson(Map<String, dynamic> json) => MessageData(
        id: json['id'] as String,
        anonymousId: json['anonymous_id'] as String,
        content: json['content'] as String,
        replyTo: json['reply_to'] as String?,
        replyContent: json['reply_content'] as String?,
        createdAt: json['created_at'] as String,
        reactions: (json['reactions'] as List<dynamic>? ?? [])
            .map((e) => ReactionData.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class GeofenceValidationData {
  final String decision;
  final String lifecycleState;
  final double distanceMeters;
  final bool canParticipate;

  GeofenceValidationData({
    required this.decision,
    required this.lifecycleState,
    required this.distanceMeters,
    required this.canParticipate,
  });

  factory GeofenceValidationData.fromJson(Map<String, dynamic> json) =>
      GeofenceValidationData(
        decision: json['decision'] as String,
        lifecycleState: json['lifecycle_state'] as String,
        distanceMeters: (json['distance_meters'] as num).toDouble(),
        canParticipate: json['can_participate'] as bool,
      );
}

class ApiService {
  final ApiClient client;

  ApiService(this.client);

  // Spaces
  Future<List<SpaceData>> discoverSpaces(
      double latitude, double longitude) async {
    final data = await client.getList(
      '/spaces/discover?latitude=$latitude&longitude=$longitude',
    );
    return data
        .map((e) => SpaceData.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> createSpace({
    required String name,
    String? description,
    required String visibility,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) async {
    return client.post('/spaces', body: {
      'name': name,
      'description': description,
      'visibility': visibility,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
    });
  }

  Future<SessionData> joinSpace(
    String spaceId, {
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) async {
    final response = await client.post('/spaces/$spaceId/join', body: {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
    }..removeWhere((_, v) => v == null));
    return SessionData.fromJson(response);
  }

  Future<void> leaveSpace(String spaceId) async {
    await client.post('/spaces/$spaceId/leave');
  }

  Future<List<SpaceData>> mySpaces() async {
    final data = await client.getList('/me/spaces');
    return data
        .map((e) => SpaceData.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<SpaceData>> joinedSpaces() async {
    final data = await client.getList('/me/joined-spaces');
    return data
        .map((e) => SpaceData.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Chat
  Future<List<MessageData>> getMessages(String spaceId) async {
    final data = await client.getList('/spaces/$spaceId/messages');
    return data
        .map((e) => MessageData.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MessageData> sendMessage(
      String spaceId, String sessionId, String content,
      {String? replyTo}) async {
    final response = await client.post('/spaces/$spaceId/messages', body: {
      'session_id': sessionId,
      'content': content,
      'reply_to': ?replyTo,
    });
    return MessageData.fromJson(response);
  }

  Future<void> reactToMessage(
      String messageId, String sessionId, String emoji) async {
    await client.post('/messages/$messageId/react', body: {
      'session_id': sessionId,
      'emoji': emoji,
    });
  }

  // Geofence
  Future<GeofenceValidationData> validateLocation({
    required String spaceId,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) async {
    final response = await client.post('/geofence/validate', body: {
      'space_id': spaceId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
    }..removeWhere((_, v) => v == null));
    return GeofenceValidationData.fromJson(response);
  }
}
