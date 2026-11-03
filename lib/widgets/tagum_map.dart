import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';

/// OpenStreetMap view locked to Tagum City. No API key needed.
class TagumMap extends StatelessWidget {
  const TagumMap({
    super.key,
    this.controller,
    this.initialCenter,
    this.initialZoom = 13,
    this.markers = const [],
    this.onTap,
  });

  final MapController? controller;
  final LatLng? initialCenter;
  final double initialZoom;
  final List<Marker> markers;
  final void Function(LatLng)? onTap;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: initialCenter ?? tagumCenter,
        initialZoom: initialZoom,
        minZoom: 11,
        maxZoom: 18,
        cameraConstraint: CameraConstraint.containCenter(
          bounds: LatLngBounds(const LatLng(tagumMinLat, tagumMinLng),
              const LatLng(tagumMaxLat, tagumMaxLng)),
        ),
        onTap: onTap == null ? null : (_, p) => onTap!(p),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.hitchmeup.hitchmeup',
        ),
        MarkerLayer(markers: markers),
        const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
      ],
    );
  }
}

/// Current GPS position, or null with a reason if unavailable.
Future<(LatLng?, String?)> currentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return (null, 'Please turn on Location (GPS).');
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied ||
      perm == LocationPermission.deniedForever) {
    return (null, 'Location permission was not allowed.');
  }
  final pos = await Geolocator.getCurrentPosition(
      locationSettings:
          const LocationSettings(accuracy: LocationAccuracy.high));
  return (LatLng(pos.latitude, pos.longitude), null);
}
