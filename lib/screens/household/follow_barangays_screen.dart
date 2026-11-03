import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../models/app_user.dart';
import '../../data/repositories.dart';
import '../../widgets/common.dart';

class FollowBarangaysScreen extends StatefulWidget {
  const FollowBarangaysScreen({super.key});

  @override
  State<FollowBarangaysScreen> createState() => _FollowBarangaysScreenState();
}

class _FollowBarangaysScreenState extends State<FollowBarangaysScreen> {
  late final AppUser _user = context.read<AppUser>();
  late final Set<String> _selected = {..._user.followedBarangays};

  Future<void> _save() async {
    final auth = context.read<AuthRepository>();
    final notifications = context.read<PushService>();
    final now = tagumBarangays.where(_selected.contains).toList();
    final ok = await runWithFeedback(context, () async {
      await auth.setFollowedBarangays(now);
      await notifications.syncFollowedBarangays(now);
    }, successMessage: 'Saved. You will get alerts for these barangays.');
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Follow Barangays')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Choose your barangay. You will get an alert when a collector schedules a route there.',
              style: TextStyle(fontSize: 18),
            ),
          ),
          for (final b in tagumBarangays)
            CheckboxListTile(
              value: _selected.contains(b),
              onChanged: (v) => setState(
                () => v == true ? _selected.add(b) : _selected.remove(b),
              ),
              title: Text(b, style: const TextStyle(fontSize: 19)),
              visualDensity: const VisualDensity(vertical: 1),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ),
      ),
    );
  }
}
