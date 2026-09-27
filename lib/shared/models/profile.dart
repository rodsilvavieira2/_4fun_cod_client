class ProfileData {
  const ProfileData({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.name,
    required this.status,
    this.nickname,
    this.avatarUrl,
    this.avatarCrop,
    this.bannerUrl,
    this.bannerCrop,
    this.bio = '',
    this.theme,
    this.style,
    this.avatarDecorationId,
    this.nameplateId,
    this.profileEffectId,
    this.profileFrameId,
  });

  factory ProfileData.fromJson(Map<String, dynamic> json) => ProfileData(
    userId: json['userId'] as String,
    username: json['username'] as String,
    displayName: json['displayName'] as String,
    name: json['name'] as String,
    status: json['status'] as String? ?? 'OFFLINE',
    nickname: json['nickname'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    avatarCrop: (json['avatarCrop'] as Map?)?.cast<String, dynamic>(),
    bannerUrl: json['bannerUrl'] as String?,
    bannerCrop: (json['bannerCrop'] as Map?)?.cast<String, dynamic>(),
    bio: json['bio'] as String? ?? '',
    theme: (json['theme'] as Map?)?.cast<String, dynamic>(),
    style: (json['style'] as Map?)?.cast<String, dynamic>(),
    avatarDecorationId: json['avatarDecorationId'] as String?,
    nameplateId: json['nameplateId'] as String?,
    profileEffectId: json['profileEffectId'] as String?,
    profileFrameId: json['profileFrameId'] as String?,
  );

  final String userId;
  final String username;
  final String displayName;
  final String name;
  final String status;
  final String? nickname;
  final String? avatarUrl;
  final Map<String, dynamic>? avatarCrop;
  final String? bannerUrl;
  final Map<String, dynamic>? bannerCrop;
  final String bio;
  final Map<String, dynamic>? theme;
  final Map<String, dynamic>? style;
  final String? avatarDecorationId;
  final String? nameplateId;
  final String? profileEffectId;
  final String? profileFrameId;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'username': username,
    'displayName': displayName,
    'name': name,
    'status': status,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
    'avatarCrop': avatarCrop,
    'bannerUrl': bannerUrl,
    'bannerCrop': bannerCrop,
    'bio': bio,
    'theme': theme,
    'style': style,
    'avatarDecorationId': avatarDecorationId,
    'nameplateId': nameplateId,
    'profileEffectId': profileEffectId,
    'profileFrameId': profileFrameId,
  };
}

class ProfileEditorData {
  const ProfileEditorData({
    required this.resolved,
    required this.mainResolved,
    required this.main,
    this.server,
  });

  factory ProfileEditorData.fromJson(Map<String, dynamic> json) =>
      ProfileEditorData(
        resolved: ProfileData.fromJson(
          (json['resolved'] as Map).cast<String, dynamic>(),
        ),
        mainResolved: ProfileData.fromJson(
          ((json['mainResolved'] ?? json['resolved']) as Map)
              .cast<String, dynamic>(),
        ),
        main: (json['main'] as Map).cast<String, dynamic>(),
        server: (json['server'] as Map?)?.cast<String, dynamic>(),
      );

  final ProfileData resolved;
  final ProfileData mainResolved;
  final Map<String, dynamic> main;
  final Map<String, dynamic>? server;
}

class CosmeticItem {
  const CosmeticItem({
    required this.id,
    required this.name,
    required this.category,
    required this.visual,
    required this.owned,
    required this.equippedMain,
    required this.equippedServers,
  });

  factory CosmeticItem.fromJson(Map<String, dynamic> json) => CosmeticItem(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String,
    visual: (json['visual'] as Map).cast<String, dynamic>(),
    owned: json['owned'] as bool? ?? false,
    equippedMain: json['equippedMain'] as bool? ?? false,
    equippedServers:
        (json['equippedServers'] as List?)?.cast<String>() ?? const [],
  );

  final String id;
  final String name;
  final String category;
  final Map<String, dynamic> visual;
  final bool owned;
  final bool equippedMain;
  final List<String> equippedServers;
}

class ProfileFont {
  const ProfileFont({
    required this.id,
    required this.name,
    required this.family,
    this.assetUrl,
  });
  factory ProfileFont.fromJson(Map<String, dynamic> json) => ProfileFont(
    id: json['id'] as String,
    name: json['name'] as String,
    family: json['family'] as String,
    assetUrl: json['assetUrl'] as String?,
  );
  final String id;
  final String name;
  final String family;
  final String? assetUrl;
}
