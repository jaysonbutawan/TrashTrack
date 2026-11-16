// Which barangay a map pin is in, so a household that chose "Apokon" cannot
// drop its pickup pin in Visayan Village.
//
// OpenStreetMap has no barangay boundary shapes for Tagum, only named areas,
// so this asks OSM's reverse geocoder (Nominatim) for the address of the pin.
// It is accurate inside a barangay but can be off right at a border, and it
// needs internet: when it cannot answer, the pin is allowed.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'constants.dart';

abstract class BarangayLocator {
  const BarangayLocator();

  /// Used by the screens; `main()` installs the real one. Tests keep the
  /// offline one (every pin allowed).
  static BarangayLocator instance = const OfflineBarangayLocator();

  /// The Tagum barangay at [point] (spelled as in [tagumBarangays]), or null
  /// when unknown (offline, outside Tagum, or no match).
  Future<String?> barangayAt(LatLng point);
}

/// Never knows — the pin check is skipped.
class OfflineBarangayLocator extends BarangayLocator {
  const OfflineBarangayLocator();

  @override
  Future<String?> barangayAt(LatLng point) async => null;
}

/// OSM Nominatim reverse geocoding. Its usage policy allows at most one
/// request a second with an identifying User-Agent; answers are cached.
class NominatimBarangayLocator extends BarangayLocator {
  NominatimBarangayLocator({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  final _cache = <String, String?>{};
  DateTime _last = DateTime(2000);
  Future<void> _queue = Future.value();

  @override
  Future<String?> barangayAt(LatLng point) {
    if (!isInsideTagum(point)) return Future.value(null);
    // ~10 m grid, so small pin nudges reuse the answer.
    final key =
        '${point.latitude.toStringAsFixed(4)},'
        '${point.longitude.toStringAsFixed(4)}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    final result = _queue.then((_) => _ask(point, key));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<String?> _ask(LatLng p, String key) async {
    if (_cache.containsKey(key)) return _cache[key];
    final wait =
        const Duration(milliseconds: 1100) - DateTime.now().difference(_last);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
    try {
      final res = await _client
          .get(
            Uri.https('nominatim.openstreetmap.org', '/reverse', {
              'format': 'jsonv2',
              'zoom': '14',
              'lat': '${p.latitude}',
              'lon': '${p.longitude}',
            }),
            headers: {'User-Agent': 'BoteBakalTagum/1.0 (Flutter app)'},
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null; // not cached: may recover
      final found = barangayFromAddress(
        (jsonDecode(res.body) as Map<String, dynamic>)['address'] as Map?,
      );
      return _cache[key] = found;
    } catch (_) {
      return null;
    }
  }
}

/// Picks the barangay out of a Nominatim `address` block. In the Philippines
/// barangays come back as `suburb`, `village` or `quarter`.
String? barangayFromAddress(Map? address) {
  if (address == null) return null;
  for (final field in ['suburb', 'village', 'quarter', 'neighbourhood']) {
    final match = matchBarangay(address[field] as String?);
    if (match != null) return match;
  }
  return null;
}

/// "San Miguel" → "San Miguel (Camp 4)", "Brgy. Apokon" → "Apokon".
String? matchBarangay(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)'), '')
      .replaceAll(RegExp(r'\b(barangay|brgy)\.?\b'), '')
      .replaceAll(RegExp(r'[^a-z]'), '');
  final n = norm(name);
  if (n.isEmpty) return null;
  for (final b in tagumBarangays) {
    if (norm(b) == n) return b;
  }
  return null;
}
