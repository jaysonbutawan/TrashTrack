import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories.dart';
import '../models/post.dart';
import '../theme.dart';
import 'common.dart';

/// Why a collector gives a reservation back. The household sees it, so it
/// is worded for them.
const cancelReasons = [
  'Not collected – no one was home',
  'Price not agreed',
  'Items not as posted',
  'Cannot make it today',
];

/// Asks why, then cancels the reservation (the post goes back on the map).
/// Returns true when it was cancelled.
Future<bool> cancelReservationWithReason(
  BuildContext context,
  RecyclablePost post,
) async {
  final posts = context.read<PostRepository>();
  final reason = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ReasonSheet(),
  );
  if (reason == null || !context.mounted) return false;
  return runWithFeedback(
    context,
    () => posts.cancelReservation(post.id, reason: reason),
    successMessage: 'Reservation cancelled. The post is back on the map.',
  );
}

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet();

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  static const _other = 'Other';
  String? _picked;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  String? get _reason {
    if (_picked == null) return null;
    if (_picked != _other) return _picked;
    final t = _details.text.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Cancel this pickup?',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Brand.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tell the household why. The post goes back on the map for '
                'other collectors.',
                style: TextStyle(fontSize: 15, color: Brand.inkSoft),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _picked,
                onChanged: (v) => setState(() => _picked = v),
                child: Column(
                  children: [
                    for (final r in [...cancelReasons, _other])
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: r,
                        title: Text(r, style: const TextStyle(fontSize: 17)),
                      ),
                  ],
                ),
              ),
              if (_picked == _other)
                TextField(
                  controller: _details,
                  autofocus: true,
                  maxLength: 120,
                  style: const TextStyle(fontSize: 17),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'What happened?'),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Brand.danger),
                onPressed: _reason == null
                    ? null
                    : () => Navigator.pop(context, _reason),
                icon: const Icon(Icons.cancel),
                label: const Text('Cancel Reservation'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Keep It'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
