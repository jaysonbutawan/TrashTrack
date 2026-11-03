/// Row in the `routes` table (see supabase/schema.sql).
class RouteSchedule {
  const RouteSchedule({
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

  factory RouteSchedule.fromMap(Map<String, dynamic> m) => RouteSchedule(
    id: m['id'] as String,
    collectorId: m['collector_id'] as String,
    collectorName: m['collector_name'] as String? ?? '',
    startTime: DateTime.parse(m['start_time'] as String).toLocal(),
    barangays: List<String>.from(m['barangays'] as List? ?? const []),
    note: m['note'] as String? ?? '',
  );
}
