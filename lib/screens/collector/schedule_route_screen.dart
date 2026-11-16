import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../data/repositories.dart';
import '../../models/route_schedule.dart';
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

  /// Chosen puroks per barangay; none = the whole barangay.
  final Map<String, List<String>> _puroks = {};
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
        child: Column(
          children: [
            CheckboxListTile(
              value: on,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _barangays.add(b);
                } else {
                  _barangays.remove(b);
                  _puroks.remove(b);
                }
              }),
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
            if (on) _purokRow(b),
          ],
        ),
      ),
    );
  }

  /// "Puroks: Whole barangay  [Choose]" under a ticked barangay.
  Widget _purokRow(String b) {
    final chosen = _puroks[b] ?? const [];
    return InkWell(
      onTap: () => _pickPuroks(b),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.signpost_outlined, size: 20, color: Brand.forest),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                purokSummary(chosen),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: chosen.isEmpty ? Brand.inkSoft : Brand.forest,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _pickPuroks(b),
              icon: const Icon(Icons.edit_location_alt, size: 20),
              label: Text(chosen.isEmpty ? 'Choose Purok' : 'Change'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPuroks(String b) async {
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PurokSheet(barangay: b, initial: _puroks[b] ?? const []),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (picked.isEmpty) {
        _puroks.remove(b);
      } else {
        _puroks[b] = picked;
      }
    });
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
        puroks: {
          for (final e in _puroks.entries)
            if (_barangays.contains(e.key)) e.key: e.value,
        },
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
                'Busiest first. Tick one, then choose its puroks.',
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

/// Pick puroks of one barangay: numbered chips plus named ones the collector
/// types (some puroks have names, e.g. "Purok Mabuhay"). None = whole barangay.
class _PurokSheet extends StatefulWidget {
  const _PurokSheet({required this.barangay, required this.initial});
  final String barangay;
  final List<String> initial;

  @override
  State<_PurokSheet> createState() => _PurokSheetState();
}

class _PurokSheetState extends State<_PurokSheet> {
  static const _numbered = 20;
  late final List<String> _chosen = [...widget.initial];
  late final List<String> _named = [
    for (final p in widget.initial)
      if (!_isNumbered(p)) p,
  ];
  final _custom = TextEditingController();

  static String _label(int n) => 'Purok $n';
  static bool _isNumbered(String p) =>
      RegExp(r'^Purok ([1-9]|1[0-9]|20)$').hasMatch(p);

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _toggle(String p) =>
      setState(() => _chosen.contains(p) ? _chosen.remove(p) : _chosen.add(p));

  void _addCustom() {
    var name = _custom.text.trim();
    if (name.isEmpty) return;
    if (!name.toLowerCase().startsWith('purok')) name = 'Purok $name';
    setState(() {
      if (!_named.contains(name) && !_isNumbered(name)) _named.add(name);
      if (!_chosen.contains(name)) _chosen.add(name);
      _custom.clear();
    });
  }

  /// Numbered first (in order), then named ones as added.
  List<String> get _sorted {
    int key(String p) {
      final m = RegExp(r'^Purok (\d+)$').firstMatch(p);
      return m == null ? 1000 : int.parse(m.group(1)!);
    }

    return [..._chosen]..sort((a, b) => key(a).compareTo(key(b)));
  }

  Widget _chip(String p) => FilterChip(
    label: Text(p.replaceFirst('Purok ', '')),
    selected: _chosen.contains(p),
    onSelected: (_) => _toggle(p),
    showCheckmark: false,
    labelStyle: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: _chosen.contains(p) ? Colors.white : Brand.ink,
    ),
    selectedColor: Brand.forest,
  );

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
              Text(
                'Puroks in ${widget.barangay}',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Brand.ink,
                ),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _chosen.isEmpty,
                onChanged: (_) => setState(_chosen.clear),
                title: const Text(
                  'Whole barangay',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var n = 1; n <= _numbered; n++) _chip(_label(n)),
                  for (final p in _named) _chip(p),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _custom,
                      textCapitalization: TextCapitalization.words,
                      onSubmitted: (_) => _addCustom(),
                      decoration: const InputDecoration(
                        hintText: 'Other purok, e.g. Mabuhay or 21',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Add purok',
                    onPressed: _addCustom,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context, _sorted),
                child: Text(
                  _chosen.isEmpty
                      ? 'Whole Barangay'
                      : 'Done (${_chosen.length} purok'
                            '${_chosen.length == 1 ? '' : 's'})',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
