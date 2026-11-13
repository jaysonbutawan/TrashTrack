enum UserRole { household, collector }

/// Row in the `profiles` table (see supabase/schema.sql).
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.email = '',
    this.avatarUrl = '',
    this.barangay = '',
    this.followedBarangays = const [],
    this.needsProfile = false,
  });

  final String id;
  final String name;
  final String phone;
  final UserRole role;
  final String email;

  /// Google profile picture; empty shows initials.
  final String avatarUrl;

  /// Barangay the household lives in (set on the Profile tab); empty = not set.
  final String barangay;
  final List<String> followedBarangays;

  /// True right after the first Google sign-in, until the user picks
  /// Household / Collector and enters a mobile number.
  final bool needsProfile;

  bool get isCollector => role == UserRole.collector;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    return parts.take(2).map((s) => s[0].toUpperCase()).join();
  }

  AppUser copyWith({
    String? name,
    String? phone,
    UserRole? role,
    String? barangay,
    List<String>? followedBarangays,
    bool? needsProfile,
  }) => AppUser(
    id: id,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    role: role ?? this.role,
    email: email,
    avatarUrl: avatarUrl,
    barangay: barangay ?? this.barangay,
    followedBarangays: followedBarangays ?? this.followedBarangays,
    needsProfile: needsProfile ?? this.needsProfile,
  );

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    phone: m['phone'] as String? ?? '',
    role: m['role'] == 'collector' ? UserRole.collector : UserRole.household,
    email: m['email'] as String? ?? '',
    avatarUrl: m['avatar_url'] as String? ?? '',
    barangay: m['barangay'] as String? ?? '',
    followedBarangays: List<String>.from(
      m['followed_barangays'] as List? ?? const [],
    ),
    // The sign-up trigger leaves role empty until the user completes setup.
    needsProfile: m['role'] == null,
  );
}
