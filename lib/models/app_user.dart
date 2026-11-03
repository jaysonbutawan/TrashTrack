enum UserRole { household, collector }

/// Row in the `profiles` table (see supabase/schema.sql).
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.followedBarangays = const [],
  });

  final String id;
  final String name;
  final String phone;
  final UserRole role;
  final List<String> followedBarangays;

  bool get isCollector => role == UserRole.collector;

  AppUser copyWith({List<String>? followedBarangays}) => AppUser(
    id: id,
    name: name,
    phone: phone,
    role: role,
    followedBarangays: followedBarangays ?? this.followedBarangays,
  );

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    phone: m['phone'] as String? ?? '',
    role: m['role'] == 'collector' ? UserRole.collector : UserRole.household,
    followedBarangays: List<String>.from(
      m['followed_barangays'] as List? ?? const [],
    ),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'role': role.name,
    'followed_barangays': followedBarangays,
  };
}
