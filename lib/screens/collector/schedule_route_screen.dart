import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../data/repositories.dart';
import '../../route_planner.dart';
import '../../theme.dart';
import '../../widgets/barangay_demand.dart';
import '../../widgets/common.dart';

class ScheduleRouteScreen extends StatefulWidget {
  const ScheduleRouteScreen({super.key, this.initialBarangays = const []});

  /// Barangays already ticked (from a suggestion).
  final List<String> initialBarangays;

  @override
  State<ScheduleRouteScreen> createState() => _ScheduleRouteScreenState();
}

class _ScheduleRouteScreenState extends State<ScheduleRouteScreen> {
  DateTime? _date;
  TimeOfDay? _time;
  late final Set<String> _barangays = {...widget.initialBarangays};
  final _note = TextEditingController();

  /// What is waiting in each barangay, busiest first (empty until loaded).
  List<BarangayDemand> _demand = const [];

  @override
  void initState() {
    super.initState();
    _loadDemand();
  }

  Future<void> _loadDemand() async {
    try {
      final posts = await context.read<PostRepository>().availablePosts().first;
      if (!mounted) return;
      final routes = await context
          .read<RouteRepository>()
          .routesFor(tagumBarangays)
          .first;
      if (mounted) setState(() => _demand = rankBarangays(posts, routes));
    } catch (_) {
      // Suggestions are optional; the plain list still works.
    }
  }

  Widget _barangayTile(String b, BarangayDemand? d) {
    final on = _barangays.contains(b);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
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
          onChanged: (v) => setState(
            () => v == true ? _barangays.add(b) : _barangays.remove(b),
          ),
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
          subtitle: d == null
              ? null
              : Text(
                  '${demandSummary(d)} waiting'
                  '${d.unserved ? ' · no collector yet' : ''}',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: d.unserved ? Brand.kraft : Brand.inkSoft,
                  ),
                ),
          secondary: d == null
              ? const Icon(Icons.location_on_outlined, color: Brand.inkSoft)
              : const Icon(Icons.local_fire_department, color: Brand.kraft),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
      initialDate: _date ?? now,
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (t != null) setState(() => _time = t);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_date == null || _time == null) {
      showMessage(messenger, 'Please choose the date and time.', error: true);
      return;
    }
    if (_barangays.isEmpty) {
      showMessage(
        messenger,
        'Please choose at least one barangay.',
        error: true,
      );
      return;
    }
    final start = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _time!.hour,
      _time!.minute,
    );
    if (start.isBefore(DateTime.now())) {
      showMessage(messenger, 'That time has already passed.', error: true);
      return;
    }
    final routes = context.read<RouteRepository>();
    final ok = await runWithFeedback(
      context,
      () => routes.schedule(
        startTime: start,
        barangays: tagumBarangays.where(_barangays.contains).toList(),
        note: _note.text,
      ),
      successMessage:
          'Route saved. Households in those barangays will be notified.',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      t,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Schedule a Route')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _section('1. When?'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Brand.card,
                    ),
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      _date == null
                          ? 'Date'
                          : DateFormat('MMM d').format(_date!),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Brand.card,
                    ),
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      _time == null ? 'Time' : _time!.format(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _section('2. Which barangays? (${_barangays.length} chosen)'),
          if (_demand.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                'Barangays with posts waiting are listed first.',
                style: TextStyle(fontSize: 15, color: Brand.inkSoft),
              ),
            ),
          for (final d in _demand) _barangayTile(d.barangay, d),
          for (final b in tagumBarangays)
            if (!_demand.any((d) => d.barangay == b)) _barangayTile(b, null),
          _section('Note (optional)'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _note,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'e.g. Buying bakal and bote, Php per kilo',
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.campaign),
            label: const Text('Save & Notify'),
          ),
        ),
      ),
    );
  }
}
