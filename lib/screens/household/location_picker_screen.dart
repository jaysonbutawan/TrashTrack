import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../constants.dart';
import '../../route_planner.dart' show formatDistance, metersBetween;
import '../../theme.dart';
import '../../widgets/tagum_map.dart';

typedef PreciseLocator = Future<(GpsFix?, String?)> Function({
  void Function(GpsFix)? onProgress,
});

Future<(GpsFix?, String?)> _defaultLocate({
  void Function(GpsFix)? onProgress,
}) => preciseLocation(onProgress: onProgress);

/// Opens the full-screen pin picker. Returns the chosen point, or null if
/// the user backed out.
Future<LatLng?> pickPickupLocation(
  BuildContext context, {
  LatLng? initial,
  GpsFix? fix,
  PreciseLocator locate = _defaultLocate,
}) => Navigator.push<LatLng>(
  context,
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) =>
        LocationPickerScreen(initial: initial, fix: fix, locate: locate),
  ),
);

/// "Drag the map under the pin", like Grab or Google Maps: the pin stays in
/// the middle of the screen and the user moves the map until it sits on
/// their gate. Starts on the phone's GPS position.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initial,
    this.fix,
    this.locate = _defaultLocate,
  });

  /// Where the pin starts (an existing pin). Null = start at the GPS fix.
  final LatLng? initial;

  /// A GPS reading the form already has, to skip waiting for a new one.
  final GpsFix? fix;
  final PreciseLocator locate;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = MapController();
  late LatLng _center = widget.initial ?? widget.fix?.point ?? tagumCenter;
  late GpsFix? _fix = widget.fix;
  bool _locating = false;
  String? _problem;

  /// True while a finger is moving the map (lifts the pin).
  bool _dragging = false;
  Timer? _settle;

  /// The pin follows the GPS until the user moves the map themselves.
  bool _userMoved = false;

  @override
  void initState() {
    super.initState();
    _userMoved = widget.initial != null;
    if (widget.fix == null || !widget.fix!.isPrecise) _locate();
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  Future<void> _locate({bool recenter = false}) async {
    if (recenter) _userMoved = false;
    setState(() {
      _locating = true;
      _problem = null;
    });
    final (fix, problem) = await widget.locate(
      onProgress: (f) {
        if (!mounted) return;
        setState(() => _fix = f);
        _follow(f);
      },
    );
    if (!mounted) return;
    setState(() {
      _fix = fix ?? _fix;
      _problem = problem;
      _locating = false;
    });
    if (fix != null) _follow(fix);
  }

  /// Move the pin to a GPS reading unless the user already placed it.
  void _follow(GpsFix f) {
    if (_userMoved || !isInsideTagum(f.point)) return;
    _center = f.point;
    try {
      _map.move(f.point, 18);
    } catch (_) {
      // Map not built yet; it starts at _center anyway.
    }
  }

  void _moved(LatLng center, bool byUser) {
    if (byUser) {
      _userMoved = true;
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 220), () {
        if (mounted) setState(() => _dragging = false);
      });
    }
    setState(() {
      _center = center;
      if (byUser) _dragging = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final inside = isInsideTagum(_center);
    final fix = _fix;
    final fromGps = fix == null ? null : metersBetween(fix.point, _center);
    final startAt = widget.initial ?? fix?.point;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: TagumMap(
              controller: _map,
              initialCenter: startAt,
              initialZoom: startAt == null ? 14 : 18,
              maxZoom: 19,
              onCameraMoved: _moved,
              circles: [if (fix != null) fix.accuracyCircle],
              markers: [if (fix != null) MyLocationDot.marker(fix.point)],
            ),
          ),
          // The pin, its tip exactly on the map center.
          IgnorePointer(
            child: Center(
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 150),
                offset: Offset(0, _dragging ? -0.75 : -0.5),
                child: Icon(
                  Icons.location_pin,
                  size: 60,
                  color: inside ? Brand.danger : Brand.inkSoft,
                  shadows: const [Shadow(color: Colors.black38, blurRadius: 6)],
                ),
              ),
            ),
          ),
          // Shadow dot under the pin tip.
          IgnorePointer(
            child: Center(
              child: Container(
                width: _dragging ? 10 : 6,
                height: _dragging ? 5 : 3,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(
                    color: Brand.card,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Material(
                      color: Brand.card,
                      elevation: 3,
                      borderRadius: BorderRadius.circular(16),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.pan_tool_alt, color: Brand.forest),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Drag the map so the pin is on your gate',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: Brand.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 210,
            child: FloatingActionButton(
              heroTag: 'locate',
              tooltip: 'Go to my location',
              backgroundColor: Brand.card,
              foregroundColor: const Color(0xFF1A73E8),
              onPressed: _locating
                  ? null
                  : () {
                      final f = _fix;
                      if (f != null && f.isPrecise) {
                        _userMoved = false;
                        _follow(f);
                        setState(() {});
                      } else {
                        _locate(recenter: true);
                      }
                    },
              child: _locating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _BottomPanel(
              locating: _locating,
              fix: fix,
              fromGps: fromGps,
              problem: _problem,
              inside: inside,
              onConfirm: () => Navigator.pop(context, _center),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.locating,
    required this.fix,
    required this.fromGps,
    required this.problem,
    required this.inside,
    required this.onConfirm,
  });

  final bool locating;
  final GpsFix? fix;
  final double? fromGps;
  final String? problem;
  final bool inside;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final f = fix;
    final IconData icon;
    final Color color;
    final String title;
    String? detail;

    if (!inside) {
      icon = Icons.wrong_location;
      color = Brand.danger;
      title = 'Outside Tagum City';
      detail = 'Only places inside Tagum City can be picked up.';
    } else if (f == null) {
      icon = locating ? Icons.gps_not_fixed : Icons.location_off;
      color = locating ? Brand.inkSoft : Brand.kraft;
      title = locating ? 'Finding your location…' : 'Location not found';
      detail = locating
          ? 'You can already drag the map.'
          : (problem ?? 'Drag the map to your house.');
    } else {
      icon = f.isPrecise ? Icons.gps_fixed : Icons.gps_not_fixed;
      color = f.isPrecise ? Brand.forest : Brand.kraft;
      final near = fromGps == null || fromGps! < 15;
      title = near
          ? 'Pin is at your location'
          : 'Pin is ${formatDistance(fromGps!)} from you';
      detail = locating
          ? 'GPS ${f.accuracyLabel} · getting more accurate…'
          : f.isPrecise
          ? 'GPS accurate to ${f.accuracyLabel}'
          : (problem ??
                'GPS is rough (${f.accuracyLabel}). Drag the pin to your exact gate.');
    }

    return Material(
      color: Brand.card,
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Brand.ink,
                          ),
                        ),
                        Text(
                          detail,
                          style: const TextStyle(
                            fontSize: 14.5,
                            color: Brand.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: inside ? onConfirm : null,
                icon: const Icon(Icons.check),
                label: const Text('Pickup Here'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
