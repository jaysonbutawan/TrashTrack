import 'dart:io';

import 'package:flutter/material.dart';

import '../data/repositories.dart';

import '../models/post.dart';

/// Runs [action], showing a spinner dialog and a plain-language error if it fails.
/// Returns true on success.
Future<bool> runWithFeedback(
  BuildContext context,
  Future<void> Function() action, {
  String? successMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    await action();
    navigator.pop();
    if (successMessage != null) showMessage(messenger, successMessage);
    return true;
  } catch (e) {
    navigator.pop();
    showMessage(messenger, friendlyError(e), error: true);
    return false;
  }
}

String friendlyError(Object e) {
  if (e is BackendException) return e.message;
  if (e is SocketException) return 'No internet connection. Please try again.';
  return 'Something went wrong. Please try again.';
}

void showMessage(
  ScaffoldMessengerState messenger,
  String text, {
  bool error = false,
}) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(text, style: const TextStyle(fontSize: 17)),
      backgroundColor: error ? Colors.red.shade700 : null,
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String yes = 'Yes',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(fontSize: 18)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('No', style: TextStyle(fontSize: 18)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(100, 50)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Color statusColor(PostStatus s) => switch (s) {
  PostStatus.available => Colors.green.shade700,
  PostStatus.reserved => Colors.orange.shade800,
  PostStatus.collected => Colors.blueGrey,
};

class Pill extends StatelessWidget {
  const Pill(this.text, this.color, {super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final PostStatus status;
  @override
  Widget build(BuildContext context) => Pill(status.label, statusColor(status));
}

class LabelPill extends StatelessWidget {
  const LabelPill(this.label, {super.key});
  final PostLabel label;
  @override
  Widget build(BuildContext context) => Pill(
    label.label,
    label == PostLabel.free ? Colors.teal.shade600 : Colors.indigo.shade600,
  );
}

/// Big list card for a post, used by both households and collectors.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onTap,
    this.trailing,
  });
  final RecyclablePost post;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: PostPhoto(post: post, width: 90, height: 90),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.typesLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${post.amount} • ${post.barangay}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusPill(post.status),
                        LabelPill(post.label),
                      ],
                    ),
                    if (trailing != null) ...[
                      const SizedBox(height: 8),
                      trailing!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, color: Colors.black54),
          ),
        ],
      ),
    ),
  );
}

/// Five large tappable stars. Returns 1–5, or null if cancelled.
Future<int?> askForRating(BuildContext context, String collectorName) {
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      var stars = 0;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Rate $collectorName'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < stars;
              return IconButton(
                iconSize: 44,
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => stars = i + 1),
                icon: Icon(
                  filled ? Icons.star : Icons.star_border,
                  color: Colors.amber.shade700,
                ),
              );
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(fontSize: 18)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 50)),
              onPressed: stars == 0 ? null : () => Navigator.pop(ctx, stars),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
    },
  );
}

/// Shows the post photo from a URL or local file, or a colored placeholder
/// (used by the static demo data, which has no photos).
class PostPhoto extends StatelessWidget {
  const PostPhoto({
    super.key,
    required this.post,
    this.width,
    required this.height,
  });
  final RecyclablePost post;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: post.label == PostLabel.free
          ? Colors.teal.shade100
          : Colors.indigo.shade100,
      child: Icon(
        Icons.recycling,
        size: height * 0.45,
        color: post.label == PostLabel.free
            ? Colors.teal.shade700
            : Colors.indigo.shade700,
      ),
    );
    final src = post.photoUrl;
    if (src.isEmpty) return placeholder;
    if (src.startsWith('http')) {
      return Image.network(
        src,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    return Image.file(
      File(src),
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
