import 'package:latlong2/latlong.dart';

/// The 23 barangays of Tagum City, Davao del Norte.
const List<String> tagumBarangays = [
  'Apokon',
  'Bincungan',
  'Busaon',
  'Canocotan',
  'Cuambogan',
  'La Filipina',
  'Liboganon',
  'Madaum',
  'Magdum',
  'Magugpo East',
  'Magugpo North',
  'Magugpo Poblacion',
  'Magugpo South',
  'Magugpo West',
  'Mankilam',
  'New Balamban',
  'Nueva Fuerza',
  'Pagsabangan',
  'Pandapan',
  'San Agustin',
  'San Isidro',
  'San Miguel (Camp 4)',
  'Visayan Village',
];

/// FCM topic names only allow [a-zA-Z0-9-_.~%].
String barangayTopic(String barangay) =>
    'brgy_${barangay.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';

enum RecyclableType {
  plastic('Plastic'),
  glass('Glass / Bote'),
  metal('Bakal / Metal'),
  cardboard('Cardboard / Karton'),
  paper('Paper / Papel'),
  cans('Cans / Lata'),
  appliances('Appliances');

  const RecyclableType(this.label);
  final String label;

  static RecyclableType fromName(String name) =>
      values.firstWhere((t) => t.name == name, orElse: () => plastic);
}

/// Center of Tagum City and a bounding box that covers all its barangays.
/// Posts and map views are limited to this area ("Tagum only for now").
final LatLng tagumCenter = LatLng(7.4478, 125.8078);
const double tagumMinLat = 7.33;
const double tagumMaxLat = 7.58;
const double tagumMinLng = 125.68;
const double tagumMaxLng = 125.93;

bool isInsideTagum(LatLng p) =>
    p.latitude >= tagumMinLat &&
    p.latitude <= tagumMaxLat &&
    p.longitude >= tagumMinLng &&
    p.longitude <= tagumMaxLng;
