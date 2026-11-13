import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/constants.dart';
import 'package:hitchmeup/models/post.dart';
import 'package:hitchmeup/models/route_schedule.dart';
import 'package:hitchmeup/route_planner.dart';
import 'package:latlong2/latlong.dart';

RecyclablePost post(
  String id,
  double lat,
  double lng, {
  String barangay = 'Apokon',
  double kg = 5,
  PostLabel label = PostLabel.free,
  PostStatus status = PostStatus.available,
}) => RecyclablePost(
  id: id,
  householdId: 'h',
  householdName: 'H',
  householdPhone: '',
  photoUrl: '',
  types: const [RecyclableType.plastic],
  weightKg: kg,
  location: LatLng(lat, lng),
  barangay: barangay,
  label: label,
  status: status,
  createdAt: DateTime(2026),
);

void main() {
  const start = LatLng(7.40, 125.80);

  test('visits stops in the shortest order, not the given order', () {
    // In a line going north; given out of order.
    final route = planRoute(start, [
      post('far', 7.46, 125.80),
      post('near', 7.41, 125.80),
      post('mid', 7.43, 125.80),
    ]);
    expect(route.stops.map((p) => p.id), ['near', 'mid', 'far']);
    expect(route.legMeters.length, 3);
    // ~6.6 km straight north, times the road factor.
    expect(route.totalMeters, closeTo(6640 * roadFactor, 150));
    expect(route.totalKg, 15);
    expect(route.totalMinutes, greaterThan(3 * minutesPerStop));
  });

  test('a small detour first beats doubling back later', () {
    // One stop just west of the start, three in a line to the east. Going
    // east first would mean coming all the way back for the west one.
    final stops = [
      post('w', 7.40, 125.795),
      post('e1', 7.40, 125.81),
      post('e2', 7.40, 125.82),
      post('e3', 7.40, 125.83),
    ];
    final route = planRoute(start, stops);
    expect(route.stops.map((p) => p.id), ['w', 'e1', 'e2', 'e3']);
  });

  test('more than 8 stops: every stop once, no worse than the given order', () {
    final stops = [
      for (var i = 0; i < 14; i++)
        post(
          'p$i',
          7.40 + ((i * 7) % 14) * 0.004,
          125.80 + ((i * 5) % 14) * 0.004,
        ),
    ];
    final route = planRoute(start, stops);
    expect(route.stops.map((p) => p.id).toSet().length, 14);

    var naive = 0.0;
    var at = start;
    for (final s in stops) {
      naive += metersBetween(at, s.location);
      at = s.location;
    }
    expect(route.totalMeters / roadFactor, lessThan(naive));
  });

  test('no stops', () {
    final route = planRoute(start, const []);
    expect(route.stops, isEmpty);
    expect(route.totalMeters, 0);
  });

  test('barangays ranked by posts, then kg; reserved posts ignored', () {
    final ranking = rankBarangays(
      [
        post('a1', 7.46, 125.82, barangay: 'Apokon', kg: 2),
        post(
          'a2',
          7.47,
          125.83,
          barangay: 'Apokon',
          kg: 3,
          label: PostLabel.forSale,
        ),
        post('m1', 7.42, 125.81, barangay: 'Mankilam', kg: 40),
        post('v1', 7.43, 125.79, barangay: 'Visayan Village', kg: 9),
        post(
          'x',
          7.43,
          125.79,
          barangay: 'Madaum',
          status: PostStatus.reserved,
        ),
      ],
      [
        RouteSchedule(
          id: 'r',
          collectorId: 'c',
          collectorName: 'Jun',
          startTime: DateTime(2026, 12, 1, 8),
          barangays: const ['Mankilam'],
        ),
      ],
    );
    expect(ranking.map((d) => d.barangay), [
      'Apokon',
      'Mankilam',
      'Visayan Village',
    ]);
    final apokon = ranking.first;
    expect(apokon.posts, 2);
    expect(apokon.totalKg, 5);
    expect(apokon.forSale, 1);
    expect(apokon.free, 1);
    expect(apokon.unserved, isTrue);
    expect(apokon.center.latitude, closeTo(7.465, 1e-9));
    expect(ranking[1].unserved, isFalse);
    expect(ranking[1].nextRoute!.collectorName, 'Jun');

    // Suggestions: an unserved barangay counts double.
    // Apokon 2 posts unserved (4) > Visayan 1 unserved (2) > Mankilam 1 served (1).
    expect(suggestBarangays(ranking).map((d) => d.barangay), [
      'Apokon',
      'Visayan Village',
      'Mankilam',
    ]);
    expect(suggestBarangays(ranking, count: 1).single.barangay, 'Apokon');
  });

  test('formatting', () {
    expect(formatDistance(430), '450 m');
    expect(formatDistance(2340), '2.3 km');
    expect(formatMinutes(45), '45 min');
    expect(formatMinutes(60), '1 hr');
    expect(formatMinutes(95), '1 hr 35 min');
  });
}
