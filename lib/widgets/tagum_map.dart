import 'dart:async';

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
    this.polylines = const [],
    this.circles = const [],
    this.onTap,
    this.onCameraMoved,
    this.interactive = true,
    this.maxZoom = 18,
  });

  final MapController? controller;
  final LatLng? initialCenter;
  final double initialZoom;
  final List<Marker> markers;

  /// Lines drawn under the markers (e.g. a suggested route).
  final List<Polyline> polylines;
  final void Function(LatLng)? onTap;

  /// Shaded circles (e.g. GPS accuracy) drawn under the markers.
  final List<CircleMarker> circles;

  /// Map center after every move. [byUser] is true for finger drags/zooms.
  final void Function(LatLng center, bool byUser)? onCameraMoved;

  /// False for a still preview (no dragging or zooming).
  final bool interactive;
  final double maxZoom;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: initialCenter ?? tagumCenter,
        initialZoom: initialZoom,
        minZoom: 11,
        maxZoom: maxZoom,
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
        ),
        onPositionChanged: onCameraMoved == null
            ? null
            : (camera, byUser) => onCameraMoved!(camera.center, byUser),
        cameraConstraint: CameraConstraint.containCenter(
          bounds: LatLngBounds(
            const LatLng(tagumMinLat, tagumMinLng),
            const LatLng(tagumMaxLat, tagumMaxLng),
          ),
        ),
        onTap: onTap == null ? null : (_, p) => onTap!(p),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.hitchmeup.hitchmeup',
        ),
        if (circles.isNotEmpty) CircleLayer(circles: circles),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
        // The app's large text would make the credit line overflow.
        const DefaultTextStyle(
          style: TextStyle(fontSize: 11, color: Colors.black87),
          child: SimpleAttributionWidget(
            source: Text('OpenStreetMap contributors'),
          ),
        ),
      ],
    );
  }
}

/// Blue "you are here" dot, like Google Maps.
class MyLocationDot extends StatelessWidget {
  const MyLocationDot({super.key});

  static const size = 26.0;

  static Marker marker(LatLng point) => Marker(
    point: point,
    width: size,
    height: size,
    child: const MyLocationDot(),
  );

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1A73E8),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 4),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
    ),
  );
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
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
  return (LatLng(pos.latitude, pos.longitude), null);
}

/// One GPS reading: where, and how sure the phone is (radius in meters).
class GpsFix {
  const GpsFix(this.point, this.accuracyMeters);
  final LatLng point;
  final double accuracyMeters;

  bool get isPrecise => accuracyMeters <= 25;

  /// "±8 m".
  String get accuracyLabel => '±${accuracyMeters.round()} m';

  /// Light-blue circle showing how far off the reading may be.
  CircleMarker get accuracyCircle => CircleMarker(
    point: point,
    radius: accuracyMeters,
    useRadiusInMeter: true,
    color: const Color(0xFF1A73E8).withValues(alpha: 0.15),
    borderColor: const Color(0xFF1A73E8).withValues(alpha: 0.5),
    borderStrokeWidth: 1.5,
  );
}

/// Best location the phone can give, for placing a pickup pin.
///
/// Listens to the GPS for up to [maxWait] and keeps the most accurate reading,
/// stopping early once it is within [goodEnough] meters. [onProgress] gets
/// each better reading so the map can follow while it improves (the first
/// can be the phone's last known position, which is instant).
/// Returns null plus a plain-language reason when location is unavailable.
Future<(GpsFix?, String?)> preciseLocation({
  void Function(GpsFix)? onProgress,
  Duration maxWait = const Duration(seconds: 10),
  double goodEnough = 12,
}) async {
  try {
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

    GpsFix? best;
    void offer(Position p) {
      final fix = GpsFix(LatLng(p.latitude, p.longitude), p.accuracy);
      if (best == null || fix.accuracyMeters < best!.accuracyMeters) {
        best = fix;
        onProgress?.call(fix);
      }
    }

    // Instant rough position while the GPS warms up (only if recent).
    final last = await Geolocator.getLastKnownPosition();
    if (last != null &&
        DateTime.now().difference(last.timestamp) <
            const Duration(minutes: 2)) {
      offer(last);
    }

    final done = Completer<void>();
    final sub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          ),
        ).listen(
          (p) {
            offer(p);
            if (best!.accuracyMeters <= goodEnough && !done.isCompleted) {
              done.complete();
            }
          },
          onError: (_) {
            if (!done.isCompleted) done.complete();
          },
        );
    await done.future.timeout(maxWait, onTimeout: () {});
    await sub.cancel();

    if (best == null) {
      return (
        null,
        'Could not get your location. Move near a window and try again.',
      );
    }
    // Android 12+: the user may have allowed only "approximate" location.
    if (best!.accuracyMeters > 500 &&
        await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced) {
      return (
        best,
        'Your phone shares only an approximate location. Turn on "Precise '
            'location" for this app in Settings for an exact pin.',
      );
    }
    return (best, null);
  } catch (_) {
    return (null, 'Could not get your location.');
  }
}
