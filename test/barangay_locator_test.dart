import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/barangay_locator.dart';

void main() {
  test('matches OSM names to the app barangays', () {
    expect(matchBarangay('Visayan Village'), 'Visayan Village');
    expect(matchBarangay('Brgy. Apokon'), 'Apokon');
    expect(matchBarangay('San Miguel (Camp 4)'), 'San Miguel (Camp 4)');
    expect(matchBarangay('San Miguel'), 'San Miguel (Camp 4)');
    expect(matchBarangay('Davao City'), isNull);
  });

  test('reads the barangay from a Nominatim address', () {
    // Real shape returned for 7.4335, 125.7953.
    expect(
      barangayFromAddress({
        'neighbourhood': 'Pioneer',
        'suburb': 'Visayan Village',
        'city': 'Tagum',
      }),
      'Visayan Village',
    );
    expect(barangayFromAddress({'city': 'Tagum'}), isNull);
    expect(barangayFromAddress(null), isNull);
  });
}
