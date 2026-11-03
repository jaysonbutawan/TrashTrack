import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../models/app_user.dart';
import '../../services/route_service.dart';
import '../../widgets/common.dart';

class ScheduleRouteScreen extends StatefulWidget {
  const ScheduleRouteScreen({super.key});

  @override
  State<ScheduleRouteScreen> createState() => _ScheduleRouteScreenState();
}

class _ScheduleRouteScreenState extends State<ScheduleRouteScreen> {
  DateTime? _date;
  TimeOfDay? _time;
  final Set<String> _barangays = {};
  final _note = TextEditingController();

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
        context: context, initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0));
    if (t != null) setState(() => _time = t);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_date == null || _time == null) {
      showMessage(messenger, 'Please choose the date and time.', error: true);
      return;
    }
    if (_barangays.isEmpty) {
      showMessage(messenger, 'Please choose at least one barangay.', error: true);
      return;
    }
    final start = DateTime(
        _date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
    if (start.isBefore(DateTime.now())) {
      showMessage(messenger, 'That time has already passed.', error: true);
      return;
    }
    final user = context.read<AppUser>();
    final routes = context.read<RouteService>();
    final ok = await runWithFeedback(
      context,
      () => routes.schedule(
        collector: user,
        startTime: start,
        barangays: tagumBarangays.where(_barangays.contains).toList(),
        note: _note.text,
      ),
      successMessage: 'Route saved. Households in those barangays will be notified.',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(t,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
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
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(_date == null
                      ? 'Date'
                      : DateFormat('MMM d').format(_date!)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(_time == null ? 'Time' : _time!.format(context)),
                ),
              ),
            ]),
          ),
          _section('2. Which barangays? (${_barangays.length} chosen)'),
          for (final b in tagumBarangays)
            CheckboxListTile(
              value: _barangays.contains(b),
              onChanged: (v) => setState(
                  () => v == true ? _barangays.add(b) : _barangays.remove(b)),
              title: Text(b, style: const TextStyle(fontSize: 19)),
            ),
          _section('Note (optional)'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _note,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                  hintText: 'e.g. Buying bakal and bote, Php per kilo'),
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
