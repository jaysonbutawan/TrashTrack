import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/route_schedule.dart';

class RouteService {
  RouteService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _routes =>
      _db.collection('routes');

  /// Routes from today onward, earliest first. Past routes are filtered on
  /// the device so no composite index is needed.
  List<RouteSchedule> _upcoming(QuerySnapshot<Map<String, dynamic>> s) {
    final startOfToday = DateTime.now().copyWith(
        hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    final list = s.docs
        .map(RouteSchedule.fromDoc)
        .where((r) => !r.startTime.isBefore(startOfToday))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return list;
  }

  Stream<List<RouteSchedule>> collectorRoutes(String collectorId) => _routes
      .where('collectorId', isEqualTo: collectorId)
      .snapshots()
      .map(_upcoming);

  /// Upcoming routes passing through any of [barangays].
  /// Tagum has 23 barangays, under Firestore's 30-value limit for array-contains-any.
  Stream<List<RouteSchedule>> routesFor(List<String> barangays) {
    if (barangays.isEmpty) return Stream.value(const []);
    return _routes
        .where('barangays', arrayContainsAny: barangays)
        .snapshots()
        .map(_upcoming);
  }

  /// Creating the document triggers the `notifyRouteFollowers` Cloud Function,
  /// which pushes an alert to households following these barangays.
  Future<void> schedule({
    required AppUser collector,
    required DateTime startTime,
    required List<String> barangays,
    String note = '',
  }) =>
      _routes.add({
        'collectorId': collector.uid,
        'collectorName': collector.name,
        'startTime': Timestamp.fromDate(startTime),
        'barangays': barangays,
        'note': note.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> delete(String routeId) => _routes.doc(routeId).delete();
}
