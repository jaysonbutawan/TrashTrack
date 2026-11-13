import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart' hide Locator;
import 'package:intl/intl.dart';

import '../../constants.dart';
import '../../data/repositories.dart';
import '../../models/app_user.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/post_form_widgets.dart';
import '../../widgets/role_card.dart';
import '../../widgets/tagum_map.dart';
import '../collector/route_guide_screen.dart';
import '../household/follow_barangays_screen.dart';

/// Profile tab for both roles: who you are, your details, log out.
///
/// Household: home barangay, mobile number, route alerts.
/// Collector: name, mobile number, and current location with a shortcut to
/// the Route Guide.
class ProfileTab extends StatelessWidget {
  const ProfileTab({
    super.key,
    required this.user,
    this.showAppBar = true,
    this.locate = currentLocation,
  });

  final AppUser user;

  /// False when the parent screen already shows an app bar (collector home).
  final bool showAppBar;

  /// Replaceable in tests (the real one needs the GPS plugin).
  final Locator locate;

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _ProfileHeader(user: user),
        const SizedBox(height: 8),
        _Section(
          title: 'My details',
          children: [
            if (user.isCollector)
              _Row(
                icon: Icons.badge,
                label: 'Name',
                value: user.name,
                empty: 'Add your name',
                action: 'Change',
                onTap: () => _editName(context),
              )
            else
              _Row(
                icon: Icons.home_work,
                label: 'My barangay',
                value: user.barangay,
                empty: 'Choose where you live',
                action: user.barangay.isEmpty ? 'Choose' : 'Change',
                onTap: () => _editBarangay(context),
              ),
            _Row(
              icon: Icons.phone,
              label: 'Mobile number',
              value: user.phone,
              empty: user.isCollector
                  ? 'Add a number households can call'
                  : 'Add a number collectors can call',
              action: user.phone.isEmpty ? 'Add' : 'Edit',
              onTap: () => _editPhone(context),
            ),
            if (user.email.isNotEmpty)
              _Row(
                icon: Icons.mail,
                label: 'Google account',
                value: user.email,
                empty: '',
              ),
          ],
        ),
        if (!user.isCollector)
          _Section(
            title: 'Route alerts',
            children: [
              _Row(
                icon: Icons.notifications_active,
                label: 'Barangays I follow',
                value: user.followedBarangays.isEmpty
                    ? ''
                    : user.followedBarangays.join(', '),
                empty: 'Get an alert when a collector is coming',
                action: user.followedBarangays.isEmpty ? 'Set up' : 'Change',
                onTap: () => _openFollow(context),
              ),
            ],
          ),
        if (user.isCollector)
          _Section(
            title: 'My current location',
            children: [_LocationCard(locate: locate)],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Brand.danger,
              side: const BorderSide(color: Brand.danger, width: 1.5),
              minimumSize: const Size.fromHeight(56),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
            label: const Text('Log Out'),
          ),
        ),
      ],
    );
    if (!showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: body,
    );
  }

  Future<void> _editName(BuildContext context) async {
    final auth = context.read<AuthRepository>();
    final name = await _askForName(context, user.name);
    if (name == null || name == user.name || !context.mounted) return;
    await runWithFeedback(
      context,
      () => auth.updateProfile(name: name),
      successMessage: 'Name updated.',
    );
  }

  Future<void> _editPhone(BuildContext context) async {
    final auth = context.read<AuthRepository>();
    final phone = await askForPhone(
      context,
      initial: user.phone,
      message: user.isCollector
          ? 'Households will see this number when you reserve their post.'
          : 'The collector who reserves your post will call or text you '
                'on this number.',
    );
    if (phone == null || phone == user.phone || !context.mounted) return;
    await runWithFeedback(
      context,
      () => auth.updateProfile(phone: phone),
      successMessage: 'Mobile number saved.',
    );
  }

  Future<void> _editBarangay(BuildContext context) async {
    final auth = context.read<AuthRepository>();
    final picked = await pickBarangay(
      context,
      selected: user.barangay.isEmpty ? null : user.barangay,
      followed: user.followedBarangays,
    );
    if (picked == null || picked == user.barangay || !context.mounted) return;
    await runWithFeedback(
      context,
      () => auth.updateProfile(barangay: picked),
      successMessage: 'Barangay set to $picked.',
    );
  }

  void _openFollow(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          Provider.value(value: user, child: const FollowBarangaysScreen()),
    ),
  );

  Future<void> _logout(BuildContext context) async {
    if (!await confirm(
      context,
      'Log out?',
      user.isCollector
          ? 'You can log in again any time with Google.'
          : 'You will stop getting route alerts on this phone.',
      yes: 'Log Out',
    )) {
      return;
    }
    if (!context.mounted) return;
    final auth = context.read<AuthRepository>();
    if (!user.isCollector) await context.read<PushService>().clear();
    await auth.signOut();
  }
}

Future<String?> _askForName(BuildContext context, String current) {
  final c = TextEditingController(text: current);
  final form = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Brand.card,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Your name',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Households see this name when you reserve their post.',
              style: TextStyle(fontSize: 16, color: Brand.inkSoft),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: c,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                hintText: 'Juan Dela Cruz',
                prefixIcon: Icon(Icons.badge),
              ),
              validator: (v) =>
                  (v ?? '').trim().length < 2 ? 'Enter your name' : null,
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

// ── header ──

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Brand.forestDark, Brand.forest, Color(0xFF2F7A3F)],
      ),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            color: Brand.kraft,
            shape: BoxShape.circle,
          ),
          child: CircleAvatar(
            radius: 34,
            backgroundColor: Brand.kraftLight,
            foregroundImage: user.avatarUrl.isEmpty
                ? null
                : NetworkImage(user.avatarUrl),
            child: Text(
              user.initials,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Brand.kraft,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.name.isEmpty ? 'No name yet' : user.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _HeaderChip(
                    icon: user.isCollector ? Icons.local_shipping : Icons.home,
                    text: user.role.title,
                  ),
                  if (!user.isCollector && user.barangay.isNotEmpty)
                    _HeaderChip(icon: Icons.place, text: user.barangay),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    ),
  );
}

// ── sections and rows ──

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 13.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
              color: Brand.inkSoft,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Brand.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Brand.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 60),
                children[i],
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    required this.empty,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Shown (highlighted) instead of [value] when it is empty.
  final String empty;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final missing = value.isEmpty;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: missing ? Brand.kraftLight : Brand.mint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: missing ? Brand.kraft : Brand.forest,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 14, color: Brand.inkSoft),
                  ),
                  Text(
                    missing ? empty : value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: missing ? 16 : 17.5,
                      fontWeight: missing ? FontWeight.w600 : FontWeight.w800,
                      color: missing ? Brand.kraft : Brand.ink,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null)
              TextButton(onPressed: onTap, child: Text(action!)),
          ],
        ),
      ),
    );
  }
}

// ── collector: current location ──

class _LocationCard extends StatefulWidget {
  const _LocationCard({required this.locate});
  final Locator locate;

  @override
  State<_LocationCard> createState() => _LocationCardState();
}

class _LocationCardState extends State<_LocationCard> {
  LatLng? _me;
  String? _problem;
  DateTime? _at;
  bool _locating = false;

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _problem = null;
    });
    LatLng? loc;
    String? problem;
    try {
      (loc, problem) = await widget.locate();
      if (loc != null && !isInsideTagum(loc)) {
        loc = null;
        problem = 'You are outside Tagum City.';
      }
    } catch (_) {
      problem = 'Could not get your location.';
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      _problem = problem;
      if (loc != null) {
        _me = loc;
        _at = DateTime.now();
      }
    });
  }

  void _openGuide() {
    final user = context.read<AppUser>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Provider.value(
          value: user,
          child: RouteGuideScreen(locate: widget.locate),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (me != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 190,
                child: TagumMap(
                  // New map each time so it re-centers on the new position.
                  key: ValueKey(me),
                  initialCenter: me,
                  initialZoom: 16,
                  markers: [MyLocationDot.marker(me)],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.my_location, color: Color(0xFF1A73E8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${me.latitude.toStringAsFixed(5)}, '
                        '${me.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Updated ${DateFormat.jm().format(_at!)}',
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
          ] else
            const Text(
              'Find where you are now, then let the Route Guide plan the '
              'shortest way to your reserved pickups.',
              style: TextStyle(fontSize: 16, color: Brand.inkSoft),
            ),
          if (_problem != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Brand.kraftLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_off, color: Brand.kraft),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _problem!,
                      style: const TextStyle(fontSize: 15, color: Brand.ink),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _locating ? null : _locate,
            icon: _locating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(me == null ? Icons.my_location : Icons.refresh),
            label: Text(
              _locating
                  ? 'Finding you…'
                  : me == null
                  ? 'Get My Current Location'
                  : 'Update Location',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _openGuide,
            icon: const Icon(Icons.navigation),
            label: const Text('Guide Me to My Pickups'),
          ),
        ],
      ),
    );
  }
}
