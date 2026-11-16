/// Row in the `routes` table (see supabase/schema.sql).
class RouteSchedule {
  const RouteSchedule({
    required this.id,
    required this.collectorId,
    required this.collectorName,
    required this.startTime,
    required this.barangays,
    this.note = '',
    this.puroks = const {},
  });

  final String id;
  final String collectorId;
  final String collectorName;
  final DateTime startTime;
  final List<String> barangays;
  final String note;

  /// Puroks visited per barangay. A barangay missing here (or with an empty
  /// list) means the whole barangay.
  final Map<String, List<String>> puroks;

  List<String> puroksIn(String barangay) => puroks[barangay] ?? const [];

  /// "Apokon (Purok 1, 3)" or just "Apokon" for the whole barangay.
  String areaLabel(String barangay) {
    final p = puroksIn(barangay);
    return p.isEmpty ? barangay : '$barangay (${purokSummary(p)})';
  }

  factory RouteSchedule.fromMap(Map<String, dynamic> m) => RouteSchedule(
    id: m['id'] as String,
    collectorId: m['collector_id'] as String,
    collectorName: m['collector_name'] as String? ?? '',
    startTime: DateTime.parse(m['start_time'] as String).toLocal(),
    barangays: List<String>.from(m['barangays'] as List? ?? const []),
    note: m['note'] as String? ?? '',
    puroks: {
      for (final e in (m['puroks'] as Map? ?? const {}).entries)
        e.key as String: List<String>.from(e.value as List? ?? const []),
    },
  );
}

/// "Purok 1, 3, Mabuhay" from ["Purok 1", "Purok 3", "Purok Mabuhay"].
String purokSummary(List<String> puroks) {
  if (puroks.isEmpty) return 'Whole barangay';
  final short = puroks
      .map(
        (p) => p.replaceFirst(RegExp(r'^purok\s+', caseSensitive: false), ''),
      )
      .join(', ');
  return 'Purok $short';
}
