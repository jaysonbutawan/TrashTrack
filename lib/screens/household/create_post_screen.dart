import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../services/post_service.dart';
import '../../widgets/common.dart';
import '../../widgets/tagum_map.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _map = MapController();
  File? _photo;
  final Set<RecyclableType> _types = {};
  PostLabel? _label;
  String? _barangay;
  LatLng? _pin;

  @override
  void initState() {
    super.initState();
    final followed = context.read<AppUser>().followedBarangays;
    if (followed.length == 1) _barangay = followed.first;
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker()
        .pickImage(source: source, maxWidth: 1280, imageQuality: 75);
    if (x != null) setState(() => _photo = File(x.path));
  }

  Future<void> _useMyLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    final (loc, err) = await currentLocation();
    if (loc == null) {
      showMessage(messenger, err!, error: true);
      return;
    }
    if (!isInsideTagum(loc)) {
      showMessage(messenger,
          'You seem to be outside Tagum City. Tap the map to place the pin.',
          error: true);
      return;
    }
    setState(() => _pin = loc);
    _map.move(loc, 17);
  }

  void _tapMap(LatLng p) {
    if (!isInsideTagum(p)) {
      showMessage(ScaffoldMessenger.of(context),
          'Only places inside Tagum City are allowed.',
          error: true);
      return;
    }
    setState(() => _pin = p);
  }

  String? _missing() {
    if (_photo == null) return 'Please add a photo.';
    if (_types.isEmpty) return 'Please choose at least one type.';
    if (_amount.text.trim().isEmpty) return 'Please enter the estimated amount.';
    if (_label == null) return 'Please choose For Sale or Free.';
    if (_barangay == null) return 'Please choose your barangay.';
    if (_pin == null) return 'Please place the pin on the map.';
    return null;
  }

  Future<void> _submit() async {
    final problem = _missing();
    if (problem != null) {
      showMessage(ScaffoldMessenger.of(context), problem, error: true);
      return;
    }
    final user = context.read<AppUser>();
    final posts = context.read<PostService>();
    final ok = await runWithFeedback(
      context,
      () => posts.create(
        household: user,
        photo: _photo!,
        types: RecyclableType.values.where(_types.contains).toList(),
        amount: _amount.text,
        location: _pin!,
        barangay: _barangay!,
        label: _label!,
        notes: _notes.text,
      ),
      successMessage: 'Posted! Collectors can now see it.',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post Recyclables')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _section('1. Photo'),
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_photo!, height: 220, fit: BoxFit.cover),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _pickPhoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
              ),
            ),
          ]),
          _section('2. What type?'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in RecyclableType.values)
                FilterChip(
                  label: Text(t.label),
                  selected: _types.contains(t),
                  onSelected: (v) =>
                      setState(() => v ? _types.add(t) : _types.remove(t)),
                ),
            ],
          ),
          _section('3. How much? (estimate)'),
          TextField(
            controller: _amount,
            style: const TextStyle(fontSize: 19),
            decoration: const InputDecoration(
                hintText: 'e.g. 2 sacks, about 5 kg, 1 old ref'),
          ),
          _section('4. For Sale or Free?'),
          SegmentedButton<PostLabel>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            segments: const [
              ButtonSegment(
                  value: PostLabel.forSale,
                  icon: Icon(Icons.payments),
                  label: Text('For Sale')),
              ButtonSegment(
                  value: PostLabel.free,
                  icon: Icon(Icons.volunteer_activism),
                  label: Text('Free')),
            ],
            selected: {?_label},
            onSelectionChanged: (s) =>
                setState(() => _label = s.isEmpty ? null : s.first),
          ),
          if (_label == PostLabel.forSale)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('The price is agreed with the collector at pickup.',
                  style: TextStyle(fontSize: 16, color: Colors.black54)),
            ),
          _section('5. Barangay'),
          DropdownButtonFormField<String>(
            initialValue: _barangay,
            isExpanded: true,
            style: const TextStyle(fontSize: 19, color: Colors.black),
            hint: const Text('Choose barangay'),
            items: [
              for (final b in tagumBarangays)
                DropdownMenuItem(value: b, child: Text(b)),
            ],
            onChanged: (v) => setState(() => _barangay = v),
          ),
          _section('6. Pickup location'),
          const Text('Tap the map where the collector should go.',
              style: TextStyle(fontSize: 16, color: Colors.black54)),
          const SizedBox(height: 8),
          SizedBox(
            height: 280,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: TagumMap(
                controller: _map,
                onTap: _tapMap,
                markers: [
                  if (_pin != null)
                    Marker(
                      point: _pin!,
                      width: 50,
                      height: 50,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_pin,
                          size: 50, color: Colors.red),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _useMyLocation,
            icon: const Icon(Icons.my_location),
            label: const Text('Use My Location'),
          ),
          _section('Notes (optional)'),
          TextField(
            controller: _notes,
            maxLines: 2,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
                hintText: 'e.g. Blue gate near the sari-sari store'),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send),
            label: const Text('Post Now'),
          ),
        ],
      ),
    );
  }
}
