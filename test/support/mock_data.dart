// Static sample data for designing the UI without a backend.

import 'package:latlong2/latlong.dart';

import 'package:hitchmeup/constants.dart' show RecyclableType;
import 'package:hitchmeup/models/app_user.dart';
import 'package:hitchmeup/models/post.dart';
import 'package:hitchmeup/models/route_schedule.dart';

/// Demo accounts by role (one tap on the login screen in demo mode).
final mockAccounts = <UserRole, AppUser>{
  UserRole.household: const AppUser(
    id: 'u-household-1',
    name: 'Maria Santos',
    phone: '09171234567',
    role: UserRole.household,
    email: 'household@demo.ph',
    followedBarangays: ['Magugpo Poblacion', 'Visayan Village'],
  ),
  UserRole.collector: const AppUser(
    id: 'u-collector-1',
    name: 'Jun Dela Cruz',
    phone: '09281234567',
    role: UserRole.collector,
    email: 'collector@demo.ph',
  ),
};

List<RecyclablePost> buildMockPosts() {
  final now = DateTime.now();
  RecyclablePost post(
    String id, {
    required String householdId,
    required String householdName,
    required List<RecyclableType> types,
    required double weightKg,
    required double lat,
    required double lng,
    required String barangay,
    required PostLabel label,
    PostStatus status = PostStatus.available,
    String notes = '',
    int hoursAgo = 1,
    bool reservedByDemoCollector = false,
    int? rating,
  }) => RecyclablePost(
    id: id,
    householdId: householdId,
    householdName: householdName,
    householdPhone: '09170000000',
    photoUrl: '',
    types: types,
    weightKg: weightKg,
    location: LatLng(lat, lng),
    barangay: barangay,
    label: label,
    status: status,
    notes: notes,
    createdAt: now.subtract(Duration(hours: hoursAgo)),
    reservedBy: status == PostStatus.available
        ? null
        : (reservedByDemoCollector ? 'u-collector-1' : 'u-collector-2'),
    reservedByName: status == PostStatus.available
        ? null
        : (reservedByDemoCollector ? 'Jun Dela Cruz' : 'Rodel Ampit'),
    reservedAt: status == PostStatus.available
        ? null
        : now.subtract(Duration(hours: hoursAgo, minutes: -30)),
    collectedAt: status == PostStatus.collected
        ? now.subtract(Duration(hours: hoursAgo - 1))
        : null,
    rating: rating,
  );

  return [
    // Maria's (demo household) own posts
    post(
      'p1',
      householdId: 'u-household-1',
      householdName: 'Maria Santos',
      types: [RecyclableType.plastic, RecyclableType.cans],
      weightKg: 8,
      lat: 7.4472,
      lng: 125.8065,
      barangay: 'Magugpo Poblacion',
      label: PostLabel.free,
      notes: 'Green gate beside the bakery',
      hoursAgo: 2,
    ),
    post(
      'p2',
      householdId: 'u-household-1',
      householdName: 'Maria Santos',
      types: [RecyclableType.metal],
      weightKg: 15,
      lat: 7.4480,
      lng: 125.8072,
      barangay: 'Magugpo Poblacion',
      label: PostLabel.forSale,
      status: PostStatus.reserved,
      reservedByDemoCollector: true,
      hoursAgo: 20,
    ),
    post(
      'p3',
      householdId: 'u-household-1',
      householdName: 'Maria Santos',
      types: [RecyclableType.glass],
      weightKg: 6,
      lat: 7.4469,
      lng: 125.8060,
      barangay: 'Magugpo Poblacion',
      label: PostLabel.forSale,
      status: PostStatus.collected,
      reservedByDemoCollector: true,
      hoursAgo: 48,
    ),
    post(
      'p12',
      householdId: 'u-household-1',
      householdName: 'Maria Santos',
      types: [RecyclableType.plastic, RecyclableType.cans],
      weightKg: 6.5,
      lat: 7.4474,
      lng: 125.8068,
      barangay: 'Magugpo Poblacion',
      label: PostLabel.free,
      status: PostStatus.collected,
      reservedByDemoCollector: true,
      hoursAgo: 24 * 6,
      rating: 5,
    ),
    post(
      'p13',
      householdId: 'u-household-1',
      householdName: 'Maria Santos',
      types: [RecyclableType.cardboard, RecyclableType.paper],
      weightKg: 12,
      lat: 7.4471,
      lng: 125.8063,
      barangay: 'Magugpo Poblacion',
      label: PostLabel.forSale,
      status: PostStatus.collected,
      hoursAgo: 24 * 15,
      rating: 4,
      notes: 'Boxes from the store renovation',
    ),
    post(
      'p14',
      householdId: 'u-household-1',
      householdName: 'Maria Santos',
      types: [RecyclableType.metal],
      weightKg: 20,
      lat: 7.4300,
      lng: 125.7962,
      barangay: 'Visayan Village',
      label: PostLabel.forSale,
      status: PostStatus.collected,
      reservedByDemoCollector: true,
      hoursAgo: 24 * 34,
      rating: 5,
      notes: "At Lola's house",
    ),
    // Other households around Tagum
    post(
      'p4',
      householdId: 'u-household-2',
      householdName: 'Lito Bautista',
      types: [RecyclableType.cardboard, RecyclableType.paper],
      weightKg: 4,
      lat: 7.4535,
      lng: 125.8110,
      barangay: 'Magugpo North',
      label: PostLabel.free,
      hoursAgo: 3,
    ),
    post(
      'p5',
      householdId: 'u-household-3',
      householdName: 'Ana Reyes',
      types: [RecyclableType.appliances],
      weightKg: 45,
      lat: 7.4300,
      lng: 125.7960,
      barangay: 'Visayan Village',
      label: PostLabel.forSale,
      notes: 'Heavy, need 2 people',
      hoursAgo: 5,
    ),
    post(
      'p6',
      householdId: 'u-household-4',
      householdName: 'Joy Villanueva',
      types: [RecyclableType.glass, RecyclableType.plastic],
      weightKg: 9,
      lat: 7.4625,
      lng: 125.8225,
      barangay: 'Apokon',
      label: PostLabel.forSale,
      hoursAgo: 6,
    ),
    post(
      'p7',
      householdId: 'u-household-5',
      householdName: 'Nestor Lim',
      types: [RecyclableType.metal, RecyclableType.cans],
      weightKg: 18,
      lat: 7.4180,
      lng: 125.8150,
      barangay: 'Mankilam',
      label: PostLabel.forSale,
      hoursAgo: 8,
    ),
    post(
      'p8',
      householdId: 'u-household-6',
      householdName: 'Grace Tan',
      types: [RecyclableType.paper],
      weightKg: 5,
      lat: 7.4400,
      lng: 125.8250,
      barangay: 'Magugpo East',
      label: PostLabel.free,
      hoursAgo: 10,
    ),
    post(
      'p9',
      householdId: 'u-household-7',
      householdName: 'Ramon Cruz',
      types: [RecyclableType.plastic],
      weightKg: 3.5,
      lat: 7.4710,
      lng: 125.7930,
      barangay: 'La Filipina',
      label: PostLabel.free,
      hoursAgo: 12,
    ),
    post(
      'p10',
      householdId: 'u-household-8',
      householdName: 'Elena Gomez',
      types: [RecyclableType.metal],
      weightKg: 25,
      lat: 7.4390,
      lng: 125.7990,
      barangay: 'Magugpo West',
      label: PostLabel.forSale,
      status: PostStatus.reserved,
      reservedByDemoCollector: true,
      hoursAgo: 4,
    ),
    post(
      'p11',
      householdId: 'u-household-9',
      householdName: 'Pedro Alcantara',
      types: [RecyclableType.cardboard],
      weightKg: 7,
      lat: 7.4280,
      lng: 125.8060,
      barangay: 'Magugpo South',
      label: PostLabel.free,
      hoursAgo: 1,
    ),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

List<RouteSchedule> buildMockRoutes() {
  final today = DateTime.now();
  DateTime at(int daysAhead, int hour) =>
      DateTime(today.year, today.month, today.day + daysAhead, hour);
  return [
    RouteSchedule(
      id: 'r1',
      collectorId: 'u-collector-1',
      collectorName: 'Jun Dela Cruz',
      startTime: at(1, 8),
      barangays: const ['Magugpo Poblacion', 'Magugpo North'],
      note: 'Buying bakal and bote',
    ),
    RouteSchedule(
      id: 'r2',
      collectorId: 'u-collector-2',
      collectorName: 'Rodel Ampit',
      startTime: at(2, 14),
      barangays: const ['Visayan Village', 'Apokon'],
    ),
    RouteSchedule(
      id: 'r3',
      collectorId: 'u-collector-1',
      collectorName: 'Jun Dela Cruz',
      startTime: at(4, 9),
      barangays: const ['Mankilam', 'Magugpo South'],
    ),
  ];
}

/// Past ratings for the collectors, so averages show something.
final mockPastRatings = <String, List<int>>{
  'u-collector-1': [5, 4, 5, 5],
  'u-collector-2': [4, 3],
};
