import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../data/repositories.dart';
import '../models/post.dart';
import '../theme.dart';
import 'recyclable_style.dart';

/// App-wide messenger, for messages that must outlive the current screen
/// (e.g. right after sign-in swaps the login screen away).
final rootMessenger = GlobalKey<ScaffoldMessengerState>();

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
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 17))),
          ],
        ),
        backgroundColor: error ? Brand.danger : Brand.forestDark,
      ),
    );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String yes = 'Yes',
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Brand.card,
      surfaceTintColor: Colors.transparent,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(message, style: const TextStyle(fontSize: 18)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('No', style: TextStyle(fontSize: 18)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(100, 50),
            backgroundColor: danger ? Brand.danger : null,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for a mobile number (needed once, before the first post, so the
/// collector can call). Returns null if cancelled.
Future<String?> askForPhone(BuildContext context) {
  final c = TextEditingController();
  final form = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Brand.card,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Your mobile number',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'The collector who reserves your post will call or text you '
              'on this number. We only ask once.',
              style: TextStyle(fontSize: 16, color: Brand.inkSoft),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                hintText: '09xx xxx xxxx',
                prefixIcon: Icon(Icons.phone),
              ),
              validator: (v) =>
                  (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10
                  ? 'Enter a valid mobile number'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(110, 48)),
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(ctx, c.text.trim());
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// "Just now", "3h ago", "Yesterday", "Mar 4".
String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'Yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  return DateFormat('MMM d').format(t);
}

Color statusColor(PostStatus s) => s.color;

class Pill extends StatelessWidget {
  const Pill(this.text, this.color, {super.key, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final PostStatus status;
  @override
  Widget build(BuildContext context) =>
      Pill(status.label, status.color, icon: status.icon);
}

class LabelPill extends StatelessWidget {
  const LabelPill(this.label, {super.key});
  final PostLabel label;
  @override
  Widget build(BuildContext context) =>
      Pill(label.label, label.color, icon: label.icon);
}

/// Small colored circle with the material's icon.
class TypeDot extends StatelessWidget {
  const TypeDot(this.type, {super.key, this.size = 30});
  final RecyclableType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = type.color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(type.icon, size: size * 0.58, color: c),
    );
  }
}

/// Posted → Reserved → Picked up, with the current step highlighted.
class StatusTracker extends StatelessWidget {
  const StatusTracker(this.status, {super.key});
  final PostStatus status;

  @override
  Widget build(BuildContext context) {
    const steps = ['Posted', 'Collector coming', 'Picked up'];
    const aligns = [TextAlign.left, TextAlign.center, TextAlign.right];
    final current = status.index;
    final color = status.color;

    Widget dot(int i) => Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: i <= current ? color : Brand.card,
        border: Border.all(color: i <= current ? color : Brand.line, width: 2),
      ),
      child: i < current || (i == current && i == steps.length - 1)
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : i == current
          ? const Center(
              child: CircleAvatar(radius: 4, backgroundColor: Colors.white),
            )
          : null,
    );

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 3,
                    color: i <= current ? color : Brand.line,
                  ),
                ),
              dot(i),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Expanded(
                child: Text(
                  steps[i],
                  textAlign: aligns[i],
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: i == current
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: i <= current ? Brand.ink : Brand.inkSoft,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Big list card for a post, used by both households and collectors.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onTap,
    this.trailing,
    this.showProgress = false,
    this.showStatus = true,
  });
  final RecyclablePost post;
  final VoidCallback onTap;
  final Widget? trailing;

  /// Show the Posted → Reserved → Picked up tracker (household view).
  final bool showProgress;

  /// Show the status pill (hidden when the tracker or the list already says it).
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: PostPhoto(post: post, width: 96, height: 96),
                      ),
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: post.label.color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            post.label.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final t in post.types) TypeDot(t, size: 26),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          post.types.map((t) => t.shortLabel).join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Brand.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _Meta(Icons.scale, post.amount, strong: true),
                            _Meta(Icons.place, post.barangay),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          post.status == PostStatus.collected &&
                                  post.collectedAt != null
                              ? 'Picked up ${timeAgo(post.collectedAt!)}'
                              : 'Posted ${timeAgo(post.createdAt)}',
                          style: const TextStyle(
                            fontSize: 14.5,
                            color: Brand.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showStatus && !showProgress) StatusPill(post.status),
                ],
              ),
              if (showProgress) ...[
                const SizedBox(height: 14),
                StatusTracker(post.status),
              ],
              if (trailing != null) ...[const SizedBox(height: 10), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text, {this.strong = false});
  final IconData icon;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 17, color: strong ? Brand.kraft : Brand.inkSoft),
      const SizedBox(width: 3),
      Flexible(
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
            color: strong ? Brand.kraft : Brand.inkSoft,
          ),
        ),
      ),
    ],
  );
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage(this.icon, this.text, {super.key, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: const BoxDecoration(
              color: Brand.mint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: Brand.forest),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18.5, color: Brand.inkSoft),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
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
      const words = ['', 'Poor', 'Fair', 'Good', 'Very good', 'Excellent!'];
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: Brand.card,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'How was $collectorName?',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < stars;
                  return IconButton(
                    iconSize: 44,
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => stars = i + 1),
                    icon: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: Brand.star,
                    ),
                  );
                }),
              ),
              Text(
                words[stars],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Brand.inkSoft,
                ),
              ),
            ],
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

/// Shows the post photo from a URL or local file, or a placeholder in the
/// color of its main material when there is no photo.
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
    final main = post.types.isEmpty ? null : post.types.first;
    final c = main?.color ?? Brand.forest;
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withValues(alpha: 0.16), c.withValues(alpha: 0.30)],
        ),
      ),
      child: Icon(
        main?.icon ?? Icons.recycling,
        size: height * 0.42,
        color: c.withValues(alpha: 0.85),
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
