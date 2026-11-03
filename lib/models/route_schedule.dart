import 'package:cloud_firestore/cloud_firestore.dart';

/// A collector's planned pickup route.
class RouteSchedule {
  RouteSchedule({
    required this.id,
    required this.collectorId,
    required this.collectorName,
    required this.startTime,
    required this.barangays,
    this.note = '',
  });

  final String id;
  final String collectorId;
  final String collectorName;
  final DateTime startTime;
  final List<String> barangays;
  final String note;

  factory RouteSchedule.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return RouteSchedule(
      id: doc.id,
      collectorId: d['collectorId'] as String? ?? '',
      collectorName: d['collectorName'] as String? ?? '',
      startTime: (d['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      barangays: List<String>.from(d['barangays'] as List? ?? []),
      note: d['note'] as String? ?? '',
    );
  }
}
