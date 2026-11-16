import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../data/repositories.dart';
import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../models/route_schedule.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/post_form_widgets.dart';
import '../../widgets/recyclable_style.dart';
import '../common/post_detail_screen.dart';
import '../common/profile_tab.dart';
import 'create_post_screen.dart';

void openPostForm(BuildContext context, {RecyclablePost? editing}) {
  final user = context.read<AppUser>();
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Provider.value(
        value: user,
        child: CreatePostScreen(editing: editing),
      ),
    ),
  );
}

class HouseholdHome extends StatefulWidget {
  const HouseholdHome({super.key});

  @override
  State<HouseholdHome> createState() => _HouseholdHomeState();
}

class _HouseholdHomeState extends State<HouseholdHome> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Make sure this device receives alerts for the barangays the user follows.
    final user = context.read<AppUser>();
    final n = context.read<PushService>();
    n.requestPermission().then(
      (_) => n.syncFollowedBarangays(user.followedBarangays),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          _MyPosts(user: user, onProfile: () => setState(() => _tab = 2)),
          _Routes(user: user),
          ProfileTab(user: user),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              backgroundColor: Brand.kraft,
              foregroundColor: Colors.white,
              onPressed: () => openPostForm(context),
              icon: const Icon(Icons.add_a_photo, size: 26),
              label: const Text(
                'Post Recyclables',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        height: 74,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined, size: 28),
            selectedIcon: Icon(
              Icons.inventory_2,
              size: 28,
              color: Brand.forest,
            ),
            label: 'My Posts',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined, size: 28),
            selectedIcon: Icon(
              Icons.local_shipping,
              size: 28,
              color: Brand.forest,
            ),
            label: 'Routes',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, size: 28),
            selectedIcon: Icon(Icons.person, size: 28, color: Brand.forest),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── My Posts ─────────────────────────────

enum _View { active, past }

enum _Sort {
  newest('Newest first', Icons.arrow_downward),
  oldest('Oldest first', Icons.arrow_upward),
  heaviest('Heaviest first', Icons.scale);

  const _Sort(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Quick chips under the search box. Which ones show depends on the view.
enum _Quick {
  all('All'),
  waiting('Waiting'),
  coming('Collector coming'),
  toRate('To rate'),
  rated('Rated');

  const _Quick(this.label);
  final String label;

  bool matches(RecyclablePost p) => switch (this) {
    all => true,
    waiting => p.status == PostStatus.available,
    coming => p.status == PostStatus.reserved,
    toRate => p.rating == null,
    rated => p.rating != null,
  };
}

class _Filters {
  const _Filters({this.types = const {}, this.label, this.sort = _Sort.newest});

  final Set<RecyclableType> types;
  final PostLabel? label;
  final _Sort sort;

  int get count => types.length + (label == null ? 0 : 1);

  bool matches(RecyclablePost p) =>
      (types.isEmpty || p.types.any(types.contains)) &&
      (label == null || p.label == label);
}

class _MyPosts extends StatefulWidget {
  const _MyPosts({required this.user, required this.onProfile});
  final AppUser user;
  final VoidCallback onProfile;

  @override
  State<_MyPosts> createState() => _MyPostsState();
}

class _MyPostsState extends State<_MyPosts> {
  late final Stream<List<RecyclablePost>> _posts = context
      .read<PostRepository>()
      .householdPosts(widget.user.id);
  final _search = TextEditingController();
  _View _view = _View.active;
  _Quick _quick = _Quick.all;
  _Filters _filters = const _Filters();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _isPast(RecyclablePost p) => p.status == PostStatus.collected;

  List<RecyclablePost> _visible(List<RecyclablePost> all) {
    final q = _search.text.trim().toLowerCase();
    final list = all
        .where((p) => _isPast(p) == (_view == _View.past))
        .where(_quick.matches)
        .where(_filters.matches)
        .where((p) => q.isEmpty || p.searchText.contains(q))
        .toList();
    int byDate(RecyclablePost a, RecyclablePost b) => _view == _View.past
        ? a.lastActivity.compareTo(b.lastActivity)
        : a.createdAt.compareTo(b.createdAt);
    switch (_filters.sort) {
      case _Sort.newest:
        list.sort((a, b) => byDate(b, a));
      case _Sort.oldest:
        list.sort(byDate);
      case _Sort.heaviest:
        list.sort((a, b) => b.weightKg.compareTo(a.weightKg));
    }
    return list;
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_Filters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initial: _filters),
    );
    if (result != null) setState(() => _filters = result);
  }

  void _setView(_View v) => setState(() {
    _view = v;
    _quick = _Quick.all;
  });

  void _clearAll() => setState(() {
    _search.clear();
    _quick = _Quick.all;
    _filters = const _Filters();
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RecyclablePost>>(
      stream: _posts,
      builder: (context, snap) {
        final all = snap.data ?? const <RecyclablePost>[];
        final active = all.where((p) => !_isPast(p)).toList();
        final past = all.where(_isPast).toList();
        final shown = _visible(all);
        final filtering =
            _search.text.isNotEmpty ||
            _quick != _Quick.all ||
            _filters.count > 0;

        // Green strip behind the status bar; the list scrolls below it.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: ColoredBox(
            color: Brand.forestDark,
            child: SafeArea(
              bottom: false,
              child: ColoredBox(
                color: Brand.paper,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _Header(
                        user: widget.user,
                        onProfile: widget.onProfile,
                        active: active,
                        past: past,
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ToolbarDelegate(
                        extent:
                            136 *
                            MediaQuery.textScalerOf(context)
                                .scale(1)
                                .clamp(1.0, 1.4)
                                .toDouble(),
                        child: _Toolbar(
                          search: _search,
                          onSearch: () => setState(() {}),
                          view: _view,
                          activeCount: active.length,
                          pastCount: past.length,
                          onView: _setView,
                          filterCount: _filters.count,
                          onFilter: _openFilters,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _QuickChips(
                        options: _view == _View.active
                            ? const [_Quick.all, _Quick.waiting, _Quick.coming]
                            : const [_Quick.all, _Quick.toRate, _Quick.rated],
                        counts: {
                          for (final q in _Quick.values)
                            q: (_view == _View.active ? active : past)
                                .where(q.matches)
                                .length,
                        },
                        selected: _quick,
                        onSelected: (q) => setState(() => _quick = q),
                        sort: _filters.sort,
                      ),
                    ),
                    if (snap.hasError)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyMessage(
                          Icons.wifi_off,
                          'Could not load your posts.',
                        ),
                      )
                    else if (!snap.hasData)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (shown.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: filtering
                            ? EmptyMessage(
                                Icons.search_off,
                                'Nothing matches your search or filters.',
                                action: TextButton.icon(
                                  onPressed: _clearAll,
                                  icon: const Icon(Icons.clear_all),
                                  label: const Text('Clear all'),
                                ),
                              )
                            : _view == _View.active
                            ? const EmptyMessage(
                                Icons.recycling,
                                'Nothing waiting for pickup.\nTap "Post Recyclables" to add one.',
                              )
                            : const EmptyMessage(
                                Icons.history,
                                'Your finished pickups will show here.',
                              ),
                      )
                    else if (_view == _View.active)
                      SliverList.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) =>
                            _ActiveCard(post: shown[i]),
                      )
                    else
                      ..._pastSlivers(shown),
                    const SliverToBoxAdapter(child: SizedBox(height: 110)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Past pickups grouped by month, each with its total weight.
  List<Widget> _pastSlivers(List<RecyclablePost> list) {
    final groups = <String, List<RecyclablePost>>{};
    final sortedByWeight = _filters.sort == _Sort.heaviest;
    for (final p in list) {
      final key = sortedByWeight
          ? 'All pickups'
          : DateFormat('MMMM yyyy').format(p.lastActivity);
      groups.putIfAbsent(key, () => []).add(p);
    }
    return [
      for (final e in groups.entries) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: [
                Text(
                  e.key.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13.5,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                    color: Brand.inkSoft,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(child: Divider()),
                const SizedBox(width: 10),
                Text(
                  formatKg(e.value.fold(0.0, (s, p) => s + p.weightKg)),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Brand.kraft,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: e.value.length,
          itemBuilder: (context, i) => _PastCard(post: e.value[i]),
        ),
      ],
    ];
  }
}

// ── header ──

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.onProfile,
    required this.active,
    required this.past,
  });
  final AppUser user;
  final VoidCallback onProfile;
  final List<RecyclablePost> active;
  final List<RecyclablePost> past;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Magandang umaga';
    if (h < 18) return 'Magandang hapon';
    return 'Magandang gabi';
  }

  @override
  Widget build(BuildContext context) {
    final kg = past.fold(0.0, (s, p) => s + p.weightKg);
    final coming = active.where((p) => p.status == PostStatus.reserved).length;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.forestDark, Brand.forest, Color(0xFF2F7A3F)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          // Big faint recycling mark — the app's "watermark".
          Positioned(
            right: -30,
            top: -10,
            child: Icon(
              Icons.recycling,
              size: 190,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: onProfile,
                      child: _Avatar(user: user),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_greeting,',
                            style: TextStyle(
                              fontSize: 15.5,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          Text(
                            user.firstName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'My profile',
                      iconSize: 28,
                      color: Colors.white,
                      onPressed: onProfile,
                      icon: const Icon(Icons.manage_accounts),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    children: [
                      _Stat(
                        value: formatKg(kg),
                        label: 'recycled',
                        icon: Icons.eco,
                        big: true,
                      ),
                      const SizedBox(width: 8),
                      _Stat(
                        value: '${past.length}',
                        label: past.length == 1 ? 'pickup' : 'pickups',
                        icon: Icons.task_alt,
                      ),
                      const SizedBox(width: 8),
                      _Stat(
                        value: '${active.length}',
                        label: 'active',
                        icon: coming > 0
                            ? Icons.local_shipping
                            : Icons.hourglass_top,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: const BoxDecoration(color: Brand.kraft, shape: BoxShape.circle),
    child: CircleAvatar(
      radius: 24,
      backgroundColor: Brand.kraftLight,
      foregroundImage: user.avatarUrl.isEmpty
          ? null
          : NetworkImage(user.avatarUrl),
      child: Text(
        user.initials,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: Brand.kraft,
        ),
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.icon,
    this.big = false,
  });
  final String value;
  final String label;
  final IconData icon;
  final bool big;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: big ? 4 : 3,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: big ? Brand.kraft : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── toolbar: search + Active/Past ──

class _ToolbarDelegate extends SliverPersistentHeaderDelegate {
  _ToolbarDelegate({required this.extent, required this.child});
  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Material(
        color: Brand.paper,
        elevation: overlaps ? 2 : 0,
        shadowColor: Colors.black26,
        child: child,
      );

  @override
  bool shouldRebuild(_ToolbarDelegate old) => true;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.search,
    required this.onSearch,
    required this.view,
    required this.activeCount,
    required this.pastCount,
    required this.onView,
    required this.filterCount,
    required this.onFilter,
  });

  final TextEditingController search;
  final VoidCallback onSearch;
  final _View view;
  final int activeCount;
  final int pastCount;
  final ValueChanged<_View> onView;
  final int filterCount;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  onChanged: (_) => onSearch(),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 17),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    hintText: 'Search type, barangay, collector…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(color: Brand.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(
                        color: Brand.line,
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(
                        color: Brand.forest,
                        width: 2,
                      ),
                    ),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              search.clear();
                              onSearch();
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: filterCount > 0,
                label: Text('$filterCount'),
                backgroundColor: Brand.kraft,
                child: IconButton.filledTonal(
                  tooltip: 'Filter',
                  style: IconButton.styleFrom(
                    backgroundColor: filterCount > 0 ? Brand.mint : Brand.card,
                    side: const BorderSide(color: Brand.line, width: 1.5),
                    minimumSize: const Size(52, 52),
                  ),
                  onPressed: onFilter,
                  icon: const Icon(Icons.tune, color: Brand.forest),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Brand.line.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _Segment(
                  icon: Icons.pending_actions,
                  text: 'Active',
                  count: activeCount,
                  selected: view == _View.active,
                  onTap: () => onView(_View.active),
                ),
                _Segment(
                  icon: Icons.history,
                  text: 'Past',
                  count: pastCount,
                  selected: view == _View.past,
                  onTap: () => onView(_View.past),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.text,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String text;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Brand.card : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? const [BoxShadow(color: Colors.black12, blurRadius: 4)]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? Brand.forest : Brand.inkSoft,
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: selected ? Brand.ink : Brand.inkSoft,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Brand.forest
                    : Brand.inkSoft.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : Brand.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _QuickChips extends StatelessWidget {
  const _QuickChips({
    required this.options,
    required this.counts,
    required this.selected,
    required this.onSelected,
    required this.sort,
  });
  final List<_Quick> options;
  final Map<_Quick, int> counts;
  final _Quick selected;
  final ValueChanged<_Quick> onSelected;
  final _Sort sort;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 50,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final q in options)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('${q.label} (${counts[q] ?? 0})'),
              selected: selected == q,
              showCheckmark: false,
              onSelected: (_) => onSelected(q),
            ),
          ),
        if (sort != _Sort.newest)
          Chip(
            avatar: Icon(sort.icon, size: 18, color: Brand.kraft),
            label: Text(sort.label),
          ),
      ],
    ),
  );
}

// ── cards ──

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.post});
  final RecyclablePost post;

  @override
  Widget build(BuildContext context) {
    final p = post;
    final Widget trailing;
    if (p.status == PostStatus.reserved) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Brand.reserved.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_shipping, color: Brand.reserved),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${p.reservedByName ?? 'A collector'} is coming. '
                'Agree on the price when they arrive.',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: Brand.ink,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      trailing = Row(
        children: [
          Expanded(
            child: Text(
              p.notes.isEmpty ? 'Waiting for a collector…' : '“${p.notes}”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, color: Brand.inkSoft),
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            onPressed: () => openPostForm(context, editing: p),
            icon: const Icon(Icons.edit, size: 20),
            label: const Text('Edit'),
          ),
        ],
      );
    }
    return PostCard(
      post: p,
      showProgress: true,
      trailing: trailing,
      onTap: () => openPostDetail(context, p.id),
    );
  }
}

class _PastCard extends StatelessWidget {
  const _PastCard({required this.post});
  final RecyclablePost post;

  @override
  Widget build(BuildContext context) {
    final p = post;
    final Widget trailing = p.rating == null
        ? FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: Brand.star,
              foregroundColor: Brand.ink,
              textStyle: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            onPressed: () => rateCollectorFlow(context, p),
            icon: const Icon(Icons.star_rounded),
            label: Text('Rate ${p.reservedByName ?? 'collector'}'),
          )
        : Row(
            children: [
              Expanded(
                child: Text(
                  'Collected by ${p.reservedByName ?? 'a collector'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, color: Brand.inkSoft),
                ),
              ),
              for (var i = 0; i < 5; i++)
                Icon(
                  i < p.rating!
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 22,
                  color: Brand.star,
                ),
            ],
          );
    return PostCard(
      post: p,
      showStatus: false, // every past post is collected
      trailing: trailing,
      onTap: () => openPostDetail(context, p.id),
    );
  }
}

// ── filter sheet ──

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});
  final _Filters initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Set<RecyclableType> _types = {...widget.initial.types};
  late PostLabel? _label = widget.initial.label;
  late _Sort _sort = widget.initial.sort;

  Widget _title(String t) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      t,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Filter & sort',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _types.clear();
                    _label = null;
                    _sort = _Sort.newest;
                  }),
                  child: const Text('Reset'),
                ),
              ],
            ),
            _title('Type'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in RecyclableType.values)
                  FilterChip(
                    avatar: Icon(
                      t.icon,
                      size: 18,
                      color: _types.contains(t) ? Colors.white : t.color,
                    ),
                    label: Text(t.shortLabel),
                    labelStyle: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _types.contains(t) ? Colors.white : Brand.ink,
                    ),
                    selectedColor: t.color,
                    showCheckmark: false,
                    side: BorderSide(
                      color: _types.contains(t) ? t.color : Brand.line,
                      width: 1.5,
                    ),
                    selected: _types.contains(t),
                    onSelected: (v) =>
                        setState(() => v ? _types.add(t) : _types.remove(t)),
                  ),
              ],
            ),
            _title('For Sale or Free'),
            Wrap(
              spacing: 8,
              children: [
                for (final l in [null, ...PostLabel.values])
                  ChoiceChip(
                    avatar: l == null
                        ? null
                        : Icon(l.icon, size: 18, color: l.color),
                    label: Text(l?.label ?? 'Both'),
                    selected: _label == l,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _label = l),
                  ),
              ],
            ),
            _title('Sort'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _Sort.values)
                  ChoiceChip(
                    avatar: Icon(s.icon, size: 18, color: Brand.forest),
                    label: Text(s.label),
                    selected: _sort == s,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _sort = s),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                _Filters(types: _types, label: _label, sort: _sort),
              ),
              icon: const Icon(Icons.check),
              label: const Text('Show Results'),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Routes ─────────────────────────────

/// Riders coming to the household's barangays. The home barangay (from the
/// Profile tab) is always included, so it never has to be picked again;
/// "Add barangay" offers only the ones not added yet.
class _Routes extends StatefulWidget {
  const _Routes({required this.user});
  final AppUser user;

  @override
  State<_Routes> createState() => _RoutesState();
}

class _RoutesState extends State<_Routes> {
  late List<String> _watched = _watchList(widget.user);
  late Stream<List<RouteSchedule>> _routes = _load();

  /// Home barangay first, then the others in the order they were added.
  static List<String> _watchList(AppUser u) => [
    if (u.barangay.isNotEmpty) u.barangay,
    ...u.followedBarangays.where((b) => b != u.barangay),
  ];

  Stream<List<RouteSchedule>> _load() =>
      context.read<RouteRepository>().routesFor(_watched);

  @override
  void didUpdateWidget(_Routes old) {
    super.didUpdateWidget(old);
    final now = _watchList(widget.user);
    if (now.join('|') != _watched.join('|')) {
      _watched = now;
      _routes = _load();
    }
  }

  Future<void> _saveFollowed(List<String> followed, String message) async {
    final auth = context.read<AuthRepository>();
    final push = context.read<PushService>();
    final ordered = tagumBarangays.where(followed.contains).toList();
    await runWithFeedback(context, () async {
      await auth.setFollowedBarangays(ordered);
      await push.syncFollowedBarangays(ordered);
    }, successMessage: message);
  }

  Future<void> _add() async {
    final picked = await pickBarangay(
      context,
      title: 'Add a barangay',
      alreadyAdded: _watched.toSet(),
    );
    if (picked == null || !mounted || _watched.contains(picked)) return;
    await _saveFollowed([
      ...widget.user.followedBarangays,
      picked,
    ], 'Added $picked. You will see its riders here.');
  }

  Future<void> _remove(String b) async {
    if (!await confirm(
          context,
          'Remove $b?',
          'You will stop seeing riders and alerts for $b.',
          yes: 'Remove',
        ) ||
        !mounted) {
      return;
    }
    await _saveFollowed(
      widget.user.followedBarangays.where((x) => x != b).toList(),
      'Removed $b.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.user.barangay;
    return Scaffold(
      appBar: AppBar(title: const Text('Riders Coming')),
      body: _watched.isEmpty
          ? EmptyMessage(
              Icons.add_location_alt,
              'Add your barangay to see which riders are coming and when.',
              action: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(220, 54)),
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Add My Barangay'),
              ),
            )
          : StreamBuilder<List<RouteSchedule>>(
              stream: _routes,
              builder: (context, snap) {
                final routes = snap.data ?? const <RouteSchedule>[];
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _WatchBar(
                      watched: _watched,
                      home: home,
                      onAdd: _add,
                      onRemove: _remove,
                    ),
                    if (snap.hasError)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: EmptyMessage(
                          Icons.wifi_off,
                          'Could not load routes.',
                        ),
                      )
                    else if (!snap.hasData)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      for (final b in _watched)
                        _BarangayRiders(
                          barangay: b,
                          isHome: b == home,
                          routes: routes
                              .where((r) => r.barangays.contains(b))
                              .toList(),
                        ),
                  ],
                );
              },
            ),
    );
  }
}

/// Chips of the barangays being watched, plus "Add barangay".
class _WatchBar extends StatelessWidget {
  const _WatchBar({
    required this.watched,
    required this.home,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> watched;
  final String home;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final left = tagumBarangays.length - watched.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Brand.kraftLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Brand.kraft.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notifications_active, color: Brand.kraft, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your barangays',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final b in watched)
                b == home
                    ? Chip(
                        avatar: const Icon(
                          Icons.home_rounded,
                          size: 18,
                          color: Brand.forest,
                        ),
                        label: Text(b),
                        backgroundColor: Brand.mint,
                        side: const BorderSide(color: Brand.forest),
                      )
                    : InputChip(
                        avatar: const Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: Brand.star,
                        ),
                        label: Text(b),
                        deleteButtonTooltipMessage: 'Remove',
                        onDeleted: () => onRemove(b),
                      ),
              if (left > 0)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18, color: Brand.forest),
                  label: const Text('Add barangay'),
                  labelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Brand.forest,
                  ),
                  side: const BorderSide(color: Brand.forest, width: 1.5),
                  onPressed: onAdd,
                ),
            ],
          ),
          if (home.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Your home barangay is added automatically. Change it on the '
              'Profile tab.',
              style: TextStyle(fontSize: 13.5, color: Brand.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

/// One barangay and the riders scheduled to pass there.
class _BarangayRiders extends StatelessWidget {
  const _BarangayRiders({
    required this.barangay,
    required this.isHome,
    required this.routes,
  });

  final String barangay;
  final bool isHome;
  final List<RouteSchedule> routes;

  @override
  Widget build(BuildContext context) {
    final riders = routes.map((r) => r.collectorId).toSet().length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Row(
            children: [
              Icon(
                isHome ? Icons.home_rounded : Icons.location_on,
                size: 20,
                color: isHome ? Brand.forest : Brand.inkSoft,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  barangay,
                  style: const TextStyle(
                    fontSize: 18.5,
                    fontWeight: FontWeight.w900,
                    color: Brand.ink,
                  ),
                ),
              ),
              Text(
                routes.isEmpty
                    ? 'No riders yet'
                    : '$riders rider${riders == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: routes.isEmpty ? Brand.inkSoft : Brand.forest,
                ),
              ),
            ],
          ),
        ),
        if (routes.isEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Brand.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Brand.line),
            ),
            child: const Row(
              children: [
                Icon(Icons.event_busy, color: Brand.inkSoft),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No rider has scheduled this barangay yet. You will get '
                    'an alert when one does.',
                    style: TextStyle(fontSize: 15, color: Brand.inkSoft),
                  ),
                ),
              ],
            ),
          )
        else
          for (final r in routes) _RiderCard(route: r, barangay: barangay),
      ],
    );
  }
}

class _RiderCard extends StatelessWidget {
  const _RiderCard({required this.route, required this.barangay});
  final RouteSchedule route;
  final String barangay;

  @override
  Widget build(BuildContext context) {
    final r = route;
    final t = r.startTime;
    final now = DateTime.now();
    final days = DateTime(
      t.year,
      t.month,
      t.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    final day = switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => DateFormat('EEE, MMM d').format(t),
    };
    final soon = days <= 1;
    final others = r.barangays.where((b) => b != barangay).toList();
    final initials = r.collectorName
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: soon ? Brand.forest : Brand.mint,
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: soon ? Colors.white : Brand.forest,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.collectorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w800,
                            color: Brand.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _RiderRating(collectorId: r.collectorId),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 17,
                        color: soon ? Brand.kraft : Brand.inkSoft,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '$day · ${DateFormat('h:mm a').format(t)}',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: soon ? Brand.kraft : Brand.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (r.puroksIn(barangay).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.signpost_outlined,
                            size: 17,
                            color: Brand.forest,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Only ${purokSummary(r.puroksIn(barangay))}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Brand.forest,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (others.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Also passing ${others.map(r.areaLabel).join(', ')}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Brand.inkSoft,
                        ),
                      ),
                    ),
                  if (r.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '“${r.note}”',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontStyle: FontStyle.italic,
                          color: Brand.ink,
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
}

/// "★ 4.8" next to a rider's name; nothing until they have ratings.
class _RiderRating extends StatefulWidget {
  const _RiderRating({required this.collectorId});
  final String collectorId;

  @override
  State<_RiderRating> createState() => _RiderRatingState();
}

class _RiderRatingState extends State<_RiderRating> {
  late final Stream<CollectorRating> _rating = context
      .read<PostRepository>()
      .collectorRating(widget.collectorId);

  @override
  Widget build(BuildContext context) => StreamBuilder<CollectorRating>(
    stream: _rating,
    builder: (context, snap) {
      final avg = snap.data?.average;
      if (avg == null) return const SizedBox.shrink();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 18, color: Brand.star),
          Text(
            avg.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Brand.ink,
            ),
          ),
        ],
      );
    },
  );
}
