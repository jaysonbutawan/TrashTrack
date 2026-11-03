import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { household, collector }

class AppUser {
  AppUser({
    required this.uid,
    required this.name,
    required this.phone,
    required this.role,
    this.followedBarangays = const [],
    this.ratingSum = 0,
    this.ratingCount = 0,
  });

  final String uid;
  final String name;
  final String phone;
  final UserRole role;
  final List<String> followedBarangays;
  final int ratingSum;
  final int ratingCount;

  bool get isCollector => role == UserRole.collector;
  double? get averageRating => ratingCount == 0 ? null : ratingSum / ratingCount;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return AppUser(
      uid: doc.id,
      name: d['name'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      role: d['role'] == 'collector' ? UserRole.collector : UserRole.household,
      followedBarangays: List<String>.from(d['followedBarangays'] as List? ?? []),
      ratingSum: (d['ratingSum'] as num?)?.toInt() ?? 0,
      ratingCount: (d['ratingCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'role': role.name,
        'followedBarangays': followedBarangays,
        'ratingSum': ratingSum,
        'ratingCount': ratingCount,
      };
}
