import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../data/repositories.dart';
import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/post_form_widgets.dart';
import '../../widgets/recyclable_style.dart';
import '../../widgets/tagum_map.dart';

/// Post recyclables, or edit a post that no collector has reserved yet
/// (pass [editing]).
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, this.editing});

  final RecyclablePost? editing;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _notes = TextEditingController();
  final _map = MapController();
  File? _photo;
  final Set<RecyclableType> _types = {};
  double _weight = 1;
  PostLabel? _label;
  String? _barangay;
  LatLng? _pin;
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
      _pin = e.location;
      _notes.text = e.notes;
    } else {
      final followed = context.read<AppUser>().followedBarangays;
      if (followed.length == 1) _barangay = followed.first;
    }
    _notes.addListener(_touch);
  }

  @override
  void dispose() {
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

  Future<void> _useMyLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    final (loc, err) = await currentLocation();
    if (loc == null) {
      showMessage(messenger, err!, error: true);
      return;
    }
    if (!isInsideTagum(loc)) {
      showMessage(
        messenger,
        'You seem to be outside Tagum City. Tap the map to place the pin.',
        error: true,
      );
      return;
    }
    _update(() => _pin = loc);
    _map.move(loc, 17);
  }

  void _tapMap(LatLng p) {
    if (!isInsideTagum(p)) {
      showMessage(
        ScaffoldMessenger.of(context),
        'Only places inside Tagum City are allowed.',
        error: true,
      );
      return;
    }
    _update(() => _pin = p);
  }

  // Order matches the step numbers on screen.
  List<bool> get _done => [
    _hasPhoto,
    _types.isNotEmpty,
    _weight > 0,
    _label != null,
    _barangay != null,
    _pin != null,
  ];

  String? _missing() {
    const messages = [
      'Please add a photo.',
      'Please choose at least one type.',
      'Please set the weight.',
      'Please choose For Sale or Free.',
      'Please choose your barangay.',
      'Please place the pin on the map.',
    ];
    final i = _done.indexOf(false);
    return i < 0 ? null : messages[i];
  }

  Future<void> _submit() async {
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

  Widget _labelChoice() => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in PostLabel.values) ...[
          if (l != PostLabel.values.first) const SizedBox(width: 10),
          Expanded(
            child: _ChoiceCard(
              color: l.color,
              icon: l.icon,
              title: l.label,
              subtitle: l == PostLabel.forSale
                  ? 'Collector pays you. Agree on the price at pickup.'
                  : 'Give it away. Nothing to pay.',
              selected: _label == l,
              onTap: () => _update(() => _label = l),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _locationSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 260,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              TagumMap(
                controller: _map,
                initialCenter: _pin,
                initialZoom: _pin == null ? 13 : 16,
                onTap: _tapMap,
                markers: [
                  if (_pin != null)
                    Marker(
                      point: _pin!,
                      width: 52,
                      height: 52,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_pin,
                        size: 52,
                        color: Brand.danger,
                      ),
                    ),
                ],
              ),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Brand.card.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _pin == null ? Icons.touch_app : Icons.check_circle,
                        size: 18,
                        color: _pin == null ? Brand.inkSoft : Brand.forest,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _pin == null ? 'Tap your house' : 'Pin placed',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(backgroundColor: Brand.card),
        onPressed: _useMyLocation,
        icon: const Icon(Icons.my_location),
        label: const Text('Use My Location'),
      ),
    ],
  );

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
              title: 'Barangay',
              done: done[4],
              child: BarangayField(
                value: _barangay,
                followed: user.followedBarangays,
                onChanged: (b) => _update(() => _barangay = b),
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

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : Brand.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? color : Brand.line, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 34, color: selected ? Colors.white : color),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : Brand.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.9)
                      : Brand.inkSoft,
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
