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

/// Row in the `posts` table (see supabase/schema.sql).
class RecyclablePost {
  const RecyclablePost({
    required this.id,
    required this.householdId,
    required this.householdName,
    required this.householdPhone,
    required this.photoUrl,
    required this.types,
    required this.amount,
    required this.location,
    required this.barangay,
    required this.label,
    required this.status,
    required this.createdAt,
    this.notes = '',
    this.reservedBy,
    this.reservedByName,
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
  final String amount;
  final LatLng location;
  final String barangay;
  final PostLabel label;
  final PostStatus status;
  final DateTime createdAt;
  final String notes;
  final String? reservedBy;
  final String? reservedByName;
  final DateTime? collectedAt;

  /// 1–5 stars the household gave the collector; null until rated.
  final int? rating;

  String get typesLabel => types.map((t) => t.label).join(', ');

  RecyclablePost copyWith({
    PostStatus? status,
    String? Function()? reservedBy,
    String? Function()? reservedByName,
    DateTime? Function()? collectedAt,
    int? Function()? rating,
  }) => RecyclablePost(
    id: id,
    householdId: householdId,
    householdName: householdName,
    householdPhone: householdPhone,
    photoUrl: photoUrl,
    types: types,
    amount: amount,
    location: location,
    barangay: barangay,
    label: label,
    status: status ?? this.status,
    createdAt: createdAt,
    notes: notes,
    reservedBy: reservedBy != null ? reservedBy() : this.reservedBy,
    reservedByName: reservedByName != null
        ? reservedByName()
        : this.reservedByName,
    collectedAt: collectedAt != null ? collectedAt() : this.collectedAt,
    rating: rating != null ? rating() : this.rating,
  );

  factory RecyclablePost.fromMap(Map<String, dynamic> m) => RecyclablePost(
    id: m['id'] as String,
    householdId: m['household_id'] as String,
    householdName: m['household_name'] as String? ?? '',
    householdPhone: m['household_phone'] as String? ?? '',
    photoUrl: m['photo_url'] as String? ?? '',
    types: (m['types'] as List? ?? const [])
        .map((t) => RecyclableType.fromName(t as String))
        .toList(),
    amount: m['amount'] as String? ?? '',
    location: LatLng(
      (m['lat'] as num).toDouble(),
      (m['lng'] as num).toDouble(),
    ),
    barangay: m['barangay'] as String? ?? '',
    label: PostLabel.fromDb(m['label'] as String?),
    status: PostStatus.fromName(m['status'] as String?),
    createdAt: DateTime.parse(m['created_at'] as String),
    notes: m['notes'] as String? ?? '',
    reservedBy: m['reserved_by'] as String?,
    reservedByName: m['reserved_by_name'] as String?,
    collectedAt: m['collected_at'] == null
        ? null
        : DateTime.parse(m['collected_at'] as String),
    rating: (m['rating'] as num?)?.toInt(),
  );
}

/// Input for creating a post (the server fills id, status, timestamps).
class NewPost {
  const NewPost({
    required this.photoPath,
    required this.types,
    required this.amount,
    required this.location,
    required this.barangay,
    required this.label,
    this.notes = '',
  });

  /// Local file path of the photo to upload.
  final String photoPath;
  final List<RecyclableType> types;
  final String amount;
  final LatLng location;
  final String barangay;
  final PostLabel label;
  final String notes;
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
