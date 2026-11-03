import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/constants.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('Tagum has 23 barangays, all unique', () {
    expect(tagumBarangays.length, 23);
    expect(tagumBarangays.toSet().length, 23);
  });

  test('barangay topics are valid, unique FCM topic names', () {
    final topics = tagumBarangays.map(barangayTopic).toList();
    expect(topics.toSet().length, topics.length);
    for (final t in topics) {
      expect(RegExp(r'^[a-zA-Z0-9\-_.~%]+$').hasMatch(t), isTrue, reason: t);
    }
    expect(barangayTopic('San Miguel (Camp 4)'), 'brgy_san_miguel_camp_4_');
  });

  test('Tagum bounds', () {
    expect(isInsideTagum(tagumCenter), isTrue);
    expect(
      isInsideTagum(const LatLng(7.0731, 125.6128)),
      isFalse,
    ); // Davao City
  });
}
