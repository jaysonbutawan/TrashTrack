import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../data/repositories.dart';
import '../../models/app_user.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class FollowBarangaysScreen extends StatefulWidget {
  const FollowBarangaysScreen({super.key});

  @override
  State<FollowBarangaysScreen> createState() => _FollowBarangaysScreenState();
}

class _FollowBarangaysScreenState extends State<FollowBarangaysScreen> {
  late final AppUser _user = context.read<AppUser>();
  late final Set<String> _selected = {..._user.followedBarangays};
  String _q = '';

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

  void _toggle(String b) => setState(
    () => _selected.contains(b) ? _selected.remove(b) : _selected.add(b),
  );

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = tagumBarangays
        .where((b) => b.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('My Barangays')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'Get an alert when a collector schedules a route in these '
              'barangays.',
              style: const TextStyle(fontSize: 16.5, color: Brand.inkSoft),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search barangay',
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                children: [
                  for (final b in tagumBarangays.where(_selected.contains))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        avatar: const Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: Brand.star,
                        ),
                        label: Text(b),
                        onDeleted: () => _toggle(b),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final b = list[i];
                final on = _selected.contains(b);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  child: Material(
                    color: on ? Brand.mint : Brand.card,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: on ? Brand.forest : Brand.line,
                        width: on ? 2 : 1,
                      ),
                    ),
                    child: CheckboxListTile(
                      value: on,
                      onChanged: (_) => _toggle(b),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      title: Text(
                        b,
                        style: TextStyle(
                          fontSize: 18.5,
                          fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                          color: Brand.ink,
                        ),
                      ),
                      secondary: Icon(
                        on
                            ? Icons.notifications_active
                            : Icons.location_on_outlined,
                        color: on ? Brand.forest : Brand.inkSoft,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(
              _selected.isEmpty
                  ? 'Save'
                  : 'Save (${_selected.length} followed)',
            ),
          ),
        ),
      ),
    );
  }
}
