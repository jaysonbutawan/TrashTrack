import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/models/route_schedule.dart';

void main() {
  test('puroks are read from the database and shown short', () {
    final r = RouteSchedule.fromMap({
      'id': 'r1',
      'collector_id': 'c1',
      'collector_name': 'Jun',
      'start_time': '2026-11-20T00:00:00Z',
      'barangays': ['Apokon', 'Mankilam'],
      'puroks': {
        'Apokon': ['Purok 1', 'Purok 3', 'Purok Mabuhay'],
      },
    });
    expect(r.puroksIn('Apokon'), hasLength(3));
    expect(r.areaLabel('Apokon'), 'Apokon (Purok 1, 3, Mabuhay)');
    // Not listed = the whole barangay.
    expect(r.puroksIn('Mankilam'), isEmpty);
    expect(r.areaLabel('Mankilam'), 'Mankilam');
  });

  test('older rows without puroks still load', () {
    final r = RouteSchedule.fromMap({
      'id': 'r1',
      'collector_id': 'c1',
      'start_time': '2026-11-20T00:00:00Z',
      'barangays': ['Apokon'],
    });
    expect(r.puroks, isEmpty);
    expect(purokSummary(const []), 'Whole barangay');
  });
}
