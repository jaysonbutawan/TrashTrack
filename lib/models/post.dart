import 'package:cloud_firestore/cloud_firestore.dart';
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
  forSale('For Sale'),
  free('Free');

  const PostLabel(this.label);
  final String label;

  static PostLabel fromName(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => free);
}

class RecyclablePost {
  RecyclablePost({
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
    this.notes = '',
    this.reservedBy,
    this.reservedByName,
    this.createdAt,
    this.collectedAt,
    this.rating,
  });

  final String id;
  final String householdId;
  final String householdName;
  final String householdPhone;
  final String photoUrl;
  final List<RecyclableType> types;
  final String amount;
  final LatLng location;
  final String barangay;
  final PostLabel label;
  final PostStatus status;
  final String notes;
  final String? reservedBy;
  final String? reservedByName;
  final DateTime? createdAt;
  final DateTime? collectedAt;

  /// 1–5 stars the household gave the collector; null until rated.
  final int? rating;

  factory RecyclablePost.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final geo = d['location'] as GeoPoint?;
    return RecyclablePost(
      id: doc.id,
      householdId: d['householdId'] as String? ?? '',
      householdName: d['householdName'] as String? ?? '',
      householdPhone: d['householdPhone'] as String? ?? '',
      photoUrl: d['photoUrl'] as String? ?? '',
      types: (d['types'] as List? ?? [])
          .map((t) => RecyclableType.fromName(t as String))
          .toList(),
      amount: d['amount'] as String? ?? '',
      location: geo == null ? tagumCenter : LatLng(geo.latitude, geo.longitude),
      barangay: d['barangay'] as String? ?? '',
      label: PostLabel.fromName(d['label'] as String?),
      status: PostStatus.fromName(d['status'] as String?),
      notes: d['notes'] as String? ?? '',
      reservedBy: d['reservedBy'] as String?,
      reservedByName: d['reservedByName'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      collectedAt: (d['collectedAt'] as Timestamp?)?.toDate(),
      rating: (d['rating'] as num?)?.toInt(),
    );
  }

  String get typesLabel => types.map((t) => t.label).join(', ');
}
