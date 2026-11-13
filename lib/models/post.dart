import 'package:latlong2/latlong.dart';

import '../constants.dart';

/// Lifecycle: available → reserved → collected.
/// A reservation can be cancelled (reserved → available).
enum PostStatus {
  available('Available'),
  reserved('Reserved'),
  collected('Collected');

  const PostStatus(this.label);
  final String label;

  static PostStatus fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => available);
}

enum PostLabel {
  forSale('For Sale', 'for_sale'),
  free('Free', 'free');

  const PostLabel(this.label, this.dbValue);
  final String label;

  /// Value stored in the `posts.label` column.
  final String dbValue;

  static PostLabel fromDb(String? v) =>
      values.firstWhere((l) => l.dbValue == v, orElse: () => free);
}

/// "12 kg", "2.5 kg".
String formatKg(double kg) {
  final s = kg == kg.roundToDouble()
      ? kg.toStringAsFixed(0)
      : kg.toStringAsFixed(1);
  return '$s kg';
}

/// Row in the `posts` table (see supabase/schema.sql).
class RecyclablePost {
  const RecyclablePost({
    required this.id,
    required this.householdId,
    required this.householdName,
    required this.householdPhone,
    required this.photoUrl,
    required this.types,
    required this.weightKg,
    required this.location,
    required this.barangay,
    required this.label,
    required this.status,
    required this.createdAt,
    this.notes = '',
    this.reservedBy,
    this.reservedByName,
    this.reservedAt,
    this.collectedAt,
    this.rating,
  });

  final String id;
  final String householdId;
  final String householdName;
  final String householdPhone;

  /// Public URL of the photo; empty shows a placeholder.
  final String photoUrl;
  final List<RecyclableType> types;

  /// Estimated weight the household entered.
  final double weightKg;
  final LatLng location;
  final String barangay;
  final PostLabel label;
  final PostStatus status;
  final DateTime createdAt;
  final String notes;
  final String? reservedBy;
  final String? reservedByName;
  final DateTime? reservedAt;
  final DateTime? collectedAt;

  /// 1–5 stars the household gave the collector; null until rated.
  final int? rating;

  String get amount => '~${formatKg(weightKg)}';
  String get typesLabel => types.map((t) => t.label).join(', ');
  bool get isEditable => status == PostStatus.available;

  /// When the post last changed state — used to sort history.
  DateTime get lastActivity => collectedAt ?? reservedAt ?? createdAt;

  /// Text the household search box matches against.
  String get searchText => [
    typesLabel,
    barangay,
    notes,
    reservedByName ?? '',
    label.label,
    status.label,
  ].join(' ').toLowerCase();

  RecyclablePost copyWith({
    String? photoUrl,
    List<RecyclableType>? types,
    double? weightKg,
    LatLng? location,
    String? barangay,
    PostLabel? label,
    String? notes,
    PostStatus? status,
    String? Function()? reservedBy,
    String? Function()? reservedByName,
    DateTime? Function()? reservedAt,
    DateTime? Function()? collectedAt,
    int? Function()? rating,
  }) => RecyclablePost(
    id: id,
    householdId: householdId,
    householdName: householdName,
    householdPhone: householdPhone,
    photoUrl: photoUrl ?? this.photoUrl,
    types: types ?? this.types,
    weightKg: weightKg ?? this.weightKg,
    location: location ?? this.location,
    barangay: barangay ?? this.barangay,
    label: label ?? this.label,
    status: status ?? this.status,
    createdAt: createdAt,
    notes: notes ?? this.notes,
    reservedBy: reservedBy != null ? reservedBy() : this.reservedBy,
    reservedByName: reservedByName != null
        ? reservedByName()
        : this.reservedByName,
    reservedAt: reservedAt != null ? reservedAt() : this.reservedAt,
    collectedAt: collectedAt != null ? collectedAt() : this.collectedAt,
    rating: rating != null ? rating() : this.rating,
  );

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  factory RecyclablePost.fromMap(Map<String, dynamic> m) => RecyclablePost(
    id: m['id'] as String,
    householdId: m['household_id'] as String,
    householdName: m['household_name'] as String? ?? '',
    householdPhone: m['household_phone'] as String? ?? '',
    photoUrl: m['photo_url'] as String? ?? '',
    types: (m['types'] as List? ?? const [])
        .map((t) => RecyclableType.fromName(t as String))
        .toList(),
    weightKg: (m['weight_kg'] as num? ?? 0).toDouble(),
    location: LatLng(
      (m['lat'] as num).toDouble(),
      (m['lng'] as num).toDouble(),
    ),
    barangay: m['barangay'] as String? ?? '',
    label: PostLabel.fromDb(m['label'] as String?),
    status: PostStatus.fromName(m['status'] as String?),
    createdAt: _date(m['created_at'])!,
    notes: m['notes'] as String? ?? '',
    reservedBy: m['reserved_by'] as String?,
    reservedByName: m['reserved_by_name'] as String?,
    reservedAt: _date(m['reserved_at']),
    collectedAt: _date(m['collected_at']),
    rating: (m['rating'] as num?)?.toInt(),
  );
}

/// Input for creating or editing a post (the server fills id, status,
/// household name/phone and timestamps).
class NewPost {
  const NewPost({
    required this.types,
    required this.weightKg,
    required this.location,
    required this.barangay,
    required this.label,
    this.photoPath,
    this.notes = '',
  });

  /// Local file path of a new photo to upload. Null when editing and the
  /// photo was not changed.
  final String? photoPath;
  final List<RecyclableType> types;
  final double weightKg;
  final LatLng location;
  final String barangay;
  final PostLabel label;
  final String notes;

  /// Columns written by insert/update (photo_url is added separately).
  Map<String, dynamic> toColumns() => {
    'types': types.map((t) => t.name).toList(),
    'weight_kg': weightKg,
    'lat': location.latitude,
    'lng': location.longitude,
    'barangay': barangay,
    'label': label.dbValue,
    'notes': notes.trim(),
  };
}

class CollectorRating {
  const CollectorRating(this.average, this.count);
  final double? average;
  final int count;

  factory CollectorRating.fromStars(Iterable<int> stars) {
    final list = stars.toList();
    if (list.isEmpty) return const CollectorRating(null, 0);
    return CollectorRating(
      list.reduce((a, b) => a + b) / list.length,
      list.length,
    );
  }

  String get label => average == null
      ? 'No ratings yet'
      : '★ ${average!.toStringAsFixed(1)} ($count)';
}
