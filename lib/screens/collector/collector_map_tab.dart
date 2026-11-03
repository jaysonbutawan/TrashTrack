import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../data/repositories.dart';
import '../../widgets/common.dart';
import '../../widgets/tagum_map.dart';
import '../common/post_detail_screen.dart';

class CollectorMapTab extends StatefulWidget {
  const CollectorMapTab({super.key, required this.user});
  final AppUser user;

  @override
  State<CollectorMapTab> createState() => _CollectorMapTabState();
}

class _CollectorMapTabState extends State<CollectorMapTab> {
  final _map = MapController();
  late final Stream<List<RecyclablePost>> _posts = context
      .read<PostRepository>()
      .availablePosts();

  /// Empty = show all types.
  final Set<RecyclableType> _types = {};

  /// Null = show both For Sale and Free.
  PostLabel? _label;

  bool _matches(RecyclablePost p) =>
      (_label == null || p.label == _label) &&
      (_types.isEmpty || p.types.any(_types.contains));

  Future<void> _goToMe() async {
    final messenger = ScaffoldMessenger.of(context);
    final (loc, err) = await currentLocation();
    if (loc == null) {
      showMessage(messenger, err!, error: true);
    } else if (!isInsideTagum(loc)) {
      showMessage(messenger, 'You are outside Tagum City.', error: true);
    } else {
      _map.move(loc, 16);
    }
  }

  void _showSummary(RecyclablePost p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PostCard(
                post: p,
                onTap: () {
                  Navigator.pop(ctx);
                  openPostDetail(context, p.id);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    openPostDetail(context, p.id);
                  },
                  icon: const Icon(Icons.visibility),
                  label: const Text('View & Reserve'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final l in [null, PostLabel.forSale, PostLabel.free])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(l?.label ?? 'All'),
                        selected: _label == l,
                        onSelected: (_) => setState(() => _label = l),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final t in RecyclableType.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(t.label),
                        selected: _types.contains(t),
                        onSelected: (v) => setState(
                          () => v ? _types.add(t) : _types.remove(t),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _filters(),
        Expanded(
          child: StreamBuilder<List<RecyclablePost>>(
            stream: _posts,
            builder: (context, snap) {
              final shown = (snap.data ?? []).where(_matches).toList();
              return Stack(
                children: [
                  TagumMap(
                    controller: _map,
                    markers: [
                      for (final p in shown)
                        Marker(
                          point: p.location,
                          width: 54,
                          height: 54,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            onTap: () => _showSummary(p),
                            child: Icon(
                              Icons.location_pin,
                              size: 54,
                              color: p.label == PostLabel.free
                                  ? Colors.teal.shade600
                                  : Colors.indigo.shade600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          snap.hasError
                              ? 'Could not load posts'
                              : !snap.hasData
                              ? 'Loading…'
                              : '${shown.length} available',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 10,
                    right: 10,
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Legend(Colors.indigo, 'For Sale'),
                            _Legend(Colors.teal, 'Free'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton.large(
                      heroTag: 'me',
                      tooltip: 'My location',
                      onPressed: _goToMe,
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.text);
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.location_pin, color: color, size: 22),
      Text(text, style: const TextStyle(fontSize: 15)),
    ],
  );
}
