import 'dart:io';

import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../barangay_locator.dart';
import '../../constants.dart';
import '../../data/repositories.dart';
import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../puroks.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/post_form_widgets.dart';
import '../../widgets/recyclable_style.dart';
import '../../widgets/tagum_map.dart';
import 'location_picker_screen.dart';

/// Post recyclables, or edit a post that no collector has reserved yet
/// (pass [editing]).
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({
    super.key,
    this.editing,
    this.locate = _defaultLocate,
  });

  final RecyclablePost? editing;

  /// Replaceable in tests (the real one needs the GPS plugin).
  final PreciseLocator locate;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

Future<(GpsFix?, String?)> _defaultLocate({
  void Function(GpsFix)? onProgress,
}) => preciseLocation(onProgress: onProgress);

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _notes = TextEditingController();
  File? _photo;
  final Set<RecyclableType> _types = {};
  double _weight = 1;
  PostLabel? _label;
  String? _barangay;
  String? _purok;
  LatLng? _pin;

  /// Purok choices per barangay (Purok 1–20 until the files load).
  PurokDirectory _purokList = PurokDirectory.empty;

  /// Barangay the pin is actually in (null = unknown / not checked).
  String? _pinBarangay;
  bool _checkingPin = false;
  Future<void>? _pinCheck;
  int _pinCheckId = 0;

  /// The pin is in a different barangay than the one chosen.
  bool get _pinMismatch =>
      _pin != null &&
      _barangay != null &&
      _pinBarangay != null &&
      _pinBarangay != _barangay;

  /// Latest GPS reading, shown as accuracy and passed to the picker.
  GpsFix? _fix;
  bool _locating = false;
  String? _locationProblem;

  /// The pin came from the GPS and the user has not adjusted it yet.
  bool _pinFromGps = false;

  /// Small map in the form: the pin stays in the middle, drag to move it.
  final _map = MapController();
  Timer? _dragCheck;

  /// A finger is on the map: the form must not scroll meanwhile.
  bool _touchingMap = false;
  bool _dirty = false;
  bool _phoneSaved = false;

  RecyclablePost? get _editing => widget.editing;
  bool get _isEdit => _editing != null;

  @override
  void initState() {
    super.initState();
    final e = _editing;
    if (e != null) {
      _types.addAll(e.types);
      _weight = e.weightKg;
      _label = e.label;
      _barangay = e.barangay;
      _purok = e.purok.isEmpty ? null : e.purok;
      _pin = e.location;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkPin());
      _notes.text = e.notes;
    } else {
      final user = context.read<AppUser>();
      final followed = user.followedBarangays;
      if (user.barangay.isNotEmpty) {
        _barangay = user.barangay; // set on the Profile tab
      } else if (followed.length == 1) {
        _barangay = followed.first;
      }
      // Find the house straight away, so most people only confirm the pin.
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    }
    _notes.addListener(_touch);
    PurokDirectory.load().then((d) {
      if (mounted) setState(() => _purokList = d);
    }, onError: (_) {});
  }

  /// Asks which barangay the pin is in. Only the latest pin counts.
  void _checkPin() {
    final pin = _pin;
    if (pin == null) return;
    final id = ++_pinCheckId;
    setState(() => _checkingPin = true);
    _pinCheck = BarangayLocator.instance
        .barangayAt(pin)
        .then(
          (found) {
            if (!mounted || id != _pinCheckId) return;
            setState(() {
              _pinBarangay = found;
              _checkingPin = false;
            });
          },
          onError: (_) {
            if (mounted && id == _pinCheckId) {
              setState(() => _checkingPin = false);
            }
          },
        );
  }

  void _setBarangay(String b) => _update(() {
    if (b != _barangay) _purok = null;
    _barangay = b;
  });

  @override
  void dispose() {
    _dragCheck?.cancel();
    _notes.dispose();
    super.dispose();
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// PopScope blocks the back button while there are unsaved changes, so
  /// clear the flag and pop after the rebuild.
  void _leave() {
    setState(() => _dirty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  void _update(VoidCallback change) => setState(() {
    change();
    _dirty = true;
  });

  bool get _hasPhoto => _photo != null || (_editing?.photoUrl ?? '') != '';

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1280,
      imageQuality: 75,
    );
    if (x != null) _update(() => _photo = File(x.path));
  }

  /// Reads the GPS (improving for a few seconds) and drops the pin there,
  /// unless the user already placed it themselves.
  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationProblem = null;
    });
    void use(GpsFix f) {
      if (!mounted) return;
      setState(() {
        _fix = f;
        if ((_pin == null || _pinFromGps) && isInsideTagum(f.point)) {
          _pin = f.point;
          _pinFromGps = true;
          _showPin(f.point);
        }
      });
    }

    final (fix, problem) = await widget.locate(onProgress: use);
    if (!mounted) return;
    if (fix != null) use(fix);
    if (_pinFromGps) _checkPin();
    setState(() {
      _locating = false;
      _locationProblem =
          problem ??
          (fix != null && !isInsideTagum(fix.point)
              ? 'You seem to be outside Tagum City. Set the pin by hand.'
              : null);
    });
  }

  Future<void> _adjustPin() async {
    final picked = await pickPickupLocation(
      context,
      initial: _pin,
      fix: _fix,
      locate: widget.locate,
    );
    if (picked != null) {
      _update(() {
        _pin = picked;
        _pinFromGps = false;
      });
      _showPin(picked);
      _checkPin();
    }
  }

  /// Centers the small map on [p] (after GPS or the full-screen picker).
  void _showPin(LatLng p) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _map.move(p, _pinZoom);
      } catch (_) {
        // Map not built yet; it starts at the pin anyway.
      }
    });
  }

  static const double _pinZoom = 17;

  /// The user dragged the small map: the pin is wherever the middle is now.
  void _dragged(LatLng center) {
    if (!isInsideTagum(center)) return;
    _update(() {
      _pin = center;
      _pinFromGps = false;
    });
    // Ask which barangay once the finger rests, not on every frame.
    _dragCheck?.cancel();
    _dragCheck = Timer(const Duration(milliseconds: 800), _checkPin);
  }

  // Order matches the step numbers on screen.
  List<bool> get _done => [
    _hasPhoto,
    _types.isNotEmpty,
    _weight > 0,
    _label != null,
    _barangay != null && _purok != null,
    _pin != null && !_pinMismatch,
  ];

  String? _missing() {
    final messages = [
      'Please add a photo.',
      'Please choose at least one type.',
      'Please set the weight.',
      'Please choose For Sale or Free.',
      _barangay == null
          ? 'Please choose your barangay.'
          : 'Please choose your purok.',
      _pinMismatch
          ? 'Your pin is in $_pinBarangay, not $_barangay. Move the pin '
                'inside $_barangay or change the barangay.'
          : 'Please place the pin on the map.',
    ];
    final i = _done.indexOf(false);
    return i < 0 ? null : messages[i];
  }

  Future<void> _submit() async {
    // Finish checking where the pin is before deciding.
    if (_checkingPin) await _pinCheck;
    if (!mounted) return;
    final problem = _missing();
    if (problem != null) {
      showMessage(ScaffoldMessenger.of(context), problem, error: true);
      return;
    }
    final posts = context.read<PostRepository>();
    // Collectors need a number to call; ask once, before the first post.
    if (!_isEdit && context.read<AppUser>().phone.isEmpty && !_phoneSaved) {
      final auth = context.read<AuthRepository>();
      final phone = await askForPhone(context);
      if (phone == null || !mounted) return;
      if (!await runWithFeedback(context, () => auth.updatePhone(phone))) {
        return;
      }
      _phoneSaved = true;
      if (!mounted) return;
    }
    final input = NewPost(
      photoPath: _photo?.path,
      types: RecyclableType.values.where(_types.contains).toList(),
      weightKg: _weight,
      location: _pin!,
      barangay: _barangay!,
      purok: _purok!,
      label: _label!,
      notes: _notes.text,
    );
    final ok = await runWithFeedback(
      context,
      () => _isEdit ? posts.update(_editing!.id, input) : posts.create(input),
      successMessage: _isEdit
          ? 'Changes saved.'
          : 'Posted! Collectors can now see it.',
    );
    if (ok && mounted) _leave();
  }

  Future<void> _maybeLeave() async {
    if (!_dirty ||
        await confirm(
          context,
          _isEdit ? 'Discard changes?' : 'Discard this post?',
          'What you entered will be lost.',
          yes: 'Discard',
          danger: true,
        )) {
      if (mounted) _leave();
    }
  }

  // ───────────────────────── sections ─────────────────────────

  Widget _photoSection() {
    final hasNew = _photo != null;
    final existing = _editing;
    if (!_hasPhoto) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Brand.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Brand.line, width: 2),
        ),
        child: Column(
          children: [
            const Icon(Icons.add_a_photo, size: 48, color: Brand.inkSoft),
            const SizedBox(height: 6),
            const Text(
              'A clear photo helps collectors decide faster.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Brand.inkSoft),
            ),
            const SizedBox(height: 14),
            _photoButtons(),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: hasNew
              ? Image.file(_photo!, height: 220, fit: BoxFit.cover)
              : PostPhoto(post: existing!, height: 220),
        ),
        const SizedBox(height: 10),
        _photoButtons(change: true),
      ],
    );
  }

  Widget _photoButtons({bool change = false}) => Row(
    children: [
      Expanded(
        child: FilledButton.icon(
          onPressed: () => _pickPhoto(ImageSource.camera),
          icon: const Icon(Icons.photo_camera),
          label: Text(change ? 'Retake' : 'Camera'),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(backgroundColor: Brand.card),
          onPressed: () => _pickPhoto(ImageSource.gallery),
          icon: const Icon(Icons.photo_library),
          label: const Text('Gallery'),
        ),
      ),
    ],
  );

  Widget _typeGrid() => LayoutBuilder(
    builder: (context, box) {
      final w = (box.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in RecyclableType.values)
            SizedBox(
              width: w,
              child: _TypeTile(
                type: t,
                selected: _types.contains(t),
                onTap: () => _update(
                  () => _types.contains(t) ? _types.remove(t) : _types.add(t),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _labelChoice() => Row(
    children: [
      for (final l in PostLabel.values) ...[
        if (l != PostLabel.values.first) const SizedBox(width: 10),
        Expanded(
          child: _ChoiceCard(
            color: l.color,
            icon: l.icon,
            title: l.label,
            selected: _label == l,
            onTap: () => _update(() => _label = l),
          ),
        ),
      ],
    ],
  );

  Widget _locationSection() {
    final pin = _pin;
    final fix = _fix;
    final String status;
    final IconData icon;
    final Color color;
    if (pin == null) {
      icon = _locating ? Icons.gps_not_fixed : Icons.location_off;
      color = _locating ? Brand.inkSoft : Brand.kraft;
      status = _locating
          ? 'Finding your location…'
          : (_locationProblem ?? 'Location not found. Set the pin by hand.');
    } else if (_pinFromGps && fix != null) {
      icon = fix.isPrecise ? Icons.gps_fixed : Icons.gps_not_fixed;
      color = fix.isPrecise ? Brand.forest : Brand.kraft;
      status = _locating
          ? 'Found you (${fix.accuracyLabel}) · getting more accurate…'
          : fix.isPrecise
          ? 'Found you, accurate to ${fix.accuracyLabel}. '
                'Adjust if the pin is not on your gate.'
          : (_locationProblem ??
                'Found you roughly (${fix.accuracyLabel}). '
                    'Please adjust the pin to your gate.');
    } else {
      icon = Icons.check_circle;
      color = Brand.forest;
      status = 'Pin set. Collectors will go here.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Drag the map to move the pin, which stays in the middle.
        Listener(
          onPointerDown: (_) => setState(() => _touchingMap = true),
          onPointerUp: (_) => setState(() => _touchingMap = false),
          onPointerCancel: (_) => setState(() => _touchingMap = false),
          child: SizedBox(
            height: 230,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  TagumMap(
                    controller: _map,
                    initialCenter: pin,
                    initialZoom: pin == null ? 13 : _pinZoom,
                    maxZoom: 19,
                    onCameraMoved: (center, byUser) {
                      if (byUser) _dragged(center);
                    },
                    circles: [
                      if (_pinFromGps && fix != null) fix.accuracyCircle,
                    ],
                  ),
                  // The pin's tip marks the middle of the map.
                  if (pin != null)
                    IgnorePointer(
                      child: Center(
                        child: Transform.translate(
                          offset: const Offset(0, -24),
                          child: const Icon(
                            Icons.location_pin,
                            size: 52,
                            color: Brand.danger,
                            shadows: [
                              Shadow(color: Colors.black38, blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (pin == null && _locating)
                    const Center(child: CircularProgressIndicator()),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.pan_tool_alt,
                              size: 16,
                              color: Brand.forest,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              pin == null
                                  ? 'Drag the map to place the pin'
                                  : 'Drag the map to move the pin',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Brand.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton.filledTonal(
                      tooltip: 'Full screen map',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.92),
                      ),
                      onPressed: _adjustPin,
                      icon: const Icon(Icons.open_in_full, color: Brand.forest),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: pin == null && !_locating
                      ? Brand.kraft
                      : Brand.inkSoft,
                ),
              ),
            ),
          ],
        ),
        if (_checkingPin && pin != null && _barangay != null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Checking the pin is inside your barangay…',
              style: TextStyle(fontSize: 14, color: Brand.inkSoft),
            ),
          ),
        if (_pinMismatch)
          _PinOutsideBarangay(
            pinBarangay: _pinBarangay!,
            chosen: _barangay!,
            onAdjust: _adjustPin,
            onSwitch: () => _setBarangay(_pinBarangay!),
          ),
        const SizedBox(height: 10),
        // Back to the exact GPS spot after dragging.
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            backgroundColor: Brand.card,
            side: const BorderSide(color: Brand.forest, width: 1.8),
          ),
          onPressed: _locating
              ? null
              : () {
                  _pinFromGps = true;
                  _locate();
                },
          icon: _locating
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.my_location, color: Brand.forest),
          label: const Text('Use My Exact Location'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AppUser>();
    final done = _done;
    final count = done.where((d) => d).length;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _maybeLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_isEdit ? 'Edit Post' : 'Post Recyclables')),
        body: ListView(
          // Dragging the pickup map must not scroll the form.
          physics: _touchingMap ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _StepCard(
              n: 1,
              title: 'Photo',
              done: done[0],
              child: _photoSection(),
            ),
            _StepCard(
              n: 2,
              title: 'What type?',
              hint: 'Choose all that apply',
              done: done[1],
              child: _typeGrid(),
            ),
            _StepCard(
              n: 3,
              title: 'How heavy? (estimate)',
              hint: 'Tap − or +',
              done: done[2],
              child: WeightStepper(
                value: _weight,
                onChanged: (v) => _update(() => _weight = v),
              ),
            ),
            _StepCard(
              n: 4,
              title: 'For Sale or Free?',
              done: done[3],
              child: _labelChoice(),
            ),
            _StepCard(
              n: 5,
              title: 'Barangay & Purok',
              done: done[4],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BarangayField(
                    value: _barangay,
                    followed: user.followedBarangays,
                    onChanged: _setBarangay,
                  ),
                  if (_barangay != null) ...[
                    const SizedBox(height: 14),
                    PurokChooser(
                      // Fresh search box for each barangay.
                      key: ValueKey(_barangay),
                      barangay: _barangay!,
                      options: _purokList.puroksOf(_barangay!),
                      notes: {
                        for (final p in _purokList.puroksOf(_barangay!))
                          p: _purokList.noteOf(_barangay!, p),
                      },
                      value: _purok,
                      onChanged: (p) => _update(() => _purok = p),
                    ),
                  ],
                ],
              ),
            ),
            _StepCard(
              n: 6,
              title: 'Pickup location',
              hint: 'Where should the collector go?',
              done: done[5],
              child: _locationSection(),
            ),
            _StepCard(
              title: 'Notes for the collector',
              hint: 'Optional',
              child: TextField(
                controller: _notes,
                maxLines: 2,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                  hintText: 'e.g. Blue gate near the sari-sari store',
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _SubmitBar(
          done: count,
          total: done.length,
          label: _isEdit ? 'Save Changes' : 'Post Now',
          icon: _isEdit ? Icons.save : Icons.send,
          onPressed: _submit,
        ),
      ),
    );
  }
}

// ───────────────────────── pieces ─────────────────────────

class _StepCard extends StatelessWidget {
  const _StepCard({
    this.n,
    required this.title,
    this.hint,
    this.done = false,
    required this.child,
  });

  final int? n;
  final String title;
  final String? hint;
  final bool done;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: done ? Brand.leaf : Brand.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? Brand.leaf : Brand.paper,
                  border: Border.all(
                    color: done ? Brand.leaf : Brand.line,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: done
                    ? const Icon(Icons.check, size: 20, color: Colors.white)
                    : n == null
                    ? const Icon(
                        Icons.edit_note,
                        size: 20,
                        color: Brand.inkSoft,
                      )
                    : Text(
                        '$n',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Brand.inkSoft,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Brand.ink,
                      ),
                    ),
                    if (hint != null)
                      Text(
                        hint!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Brand.inkSoft,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Large, clearly colored tile for one material type.
class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final RecyclableType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = type.color;
    return Material(
      color: selected ? c.withValues(alpha: 0.12) : Brand.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? c : Brand.line,
          width: selected ? 2.5 : 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected ? c : c.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  type.icon,
                  color: selected ? Colors.white : c,
                  size: 24,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? c : Brand.ink,
                      ),
                    ),
                    Text(
                      type.localLabel ?? type.examples,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Brand.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 22,
                color: selected ? c : Brand.line,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill: icon + "For Sale" / "Free". Fills with its color when picked.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : Brand.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? color : Brand.line, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: selected ? Colors.white : color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : Brand.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.done,
    required this.total,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final int done;
  final int total;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ready = done == total;
    return Material(
      color: Brand.card,
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: done / total,
                        minHeight: 7,
                        color: Brand.leaf,
                        backgroundColor: Brand.line,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    ready ? 'Ready!' : '$done of $total done',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: ready ? Brand.forest : Brand.inkSoft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: onPressed,
                icon: Icon(icon),
                label: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "This pin is in Visayan Village, not Apokon." with the two ways out.
class _PinOutsideBarangay extends StatelessWidget {
  const _PinOutsideBarangay({
    required this.pinBarangay,
    required this.chosen,
    required this.onAdjust,
    required this.onSwitch,
  });
  final String pinBarangay;
  final String chosen;
  final VoidCallback onAdjust;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    decoration: BoxDecoration(
      color: Brand.danger.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Brand.danger.withValues(alpha: 0.5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.wrong_location, color: Brand.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This pin is in $pinBarangay, not $chosen. '
                'Move the pin inside $chosen.',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Brand.danger,
                ),
              ),
            ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            TextButton(
              onPressed: onSwitch,
              child: Text('I live in $pinBarangay'),
            ),
            TextButton(onPressed: onAdjust, child: const Text('Move Pin')),
          ],
        ),
      ],
    ),
  );
}
