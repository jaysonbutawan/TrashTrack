import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../models/post.dart';
import '../theme.dart';

// ───────────────────────────── weight ─────────────────────────────

/// Big − [ 12 kg ] + control. Steps are 0.5 kg up to 5 kg, 1 kg up to 50 kg,
/// then 5 kg. Hold a button to change quickly; tap the number to type it.
class WeightStepper extends StatefulWidget {
  const WeightStepper({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  static const double min = 0.5;
  static const double max = 500;

  @override
  State<WeightStepper> createState() => _WeightStepperState();
}

class _WeightStepperState extends State<WeightStepper> {
  Timer? _repeat;
  late double _value = widget.value;

  @override
  void didUpdateWidget(WeightStepper old) {
    super.didUpdateWidget(old);
    _value = widget.value;
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  static double _stepUp(double v) => v < 5 ? 0.5 : (v < 50 ? 1 : 5);
  static double _stepDown(double v) => v <= 5 ? 0.5 : (v <= 50 ? 1 : 5);

  void _set(double v) {
    final next = v.clamp(WeightStepper.min, WeightStepper.max).toDouble();
    if (next == _value) return;
    HapticFeedback.selectionClick();
    setState(() => _value = next);
    widget.onChanged(next);
  }

  void _bump(int dir) =>
      _set(dir > 0 ? _value + _stepUp(_value) : _value - _stepDown(_value));

  void _startRepeat(int dir) {
    _repeat?.cancel();
    _repeat = Timer.periodic(
      const Duration(milliseconds: 110),
      (_) => _bump(dir),
    );
  }

  void _stopRepeat() => _repeat?.cancel();

  Future<void> _type() async {
    final c = TextEditingController(
      text: formatKg(_value).replaceAll(' kg', ''),
    );
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.card,
        surfaceTintColor: Colors.transparent,
        title: const Text('Enter weight'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d?)?')),
          ],
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(suffixText: 'kg'),
          onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 48)),
            onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (v != null && v > 0) _set((v * 2).round() / 2); // nearest 0.5 kg
  }

  Widget _button(IconData icon, int dir, bool enabled) => GestureDetector(
    onLongPressStart: enabled ? (_) => _startRepeat(dir) : null,
    onLongPressEnd: (_) => _stopRepeat(),
    onLongPressCancel: _stopRepeat,
    child: Material(
      color: enabled ? Brand.forest : Brand.line,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? () => _bump(dir) : null,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Icon(icon, size: 34, color: Colors.white),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final kg = formatKg(_value).replaceAll(' kg', '');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: Brand.kraftLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Brand.kraft.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _button(Icons.remove, -1, _value > WeightStepper.min),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _type,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              kg,
                              style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                color: Brand.ink,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'kg',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Brand.kraft,
                              ),
                            ),
                          ],
                        ),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit, size: 14, color: Brand.inkSoft),
                            SizedBox(width: 4),
                            Text(
                              'Tap to type',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Brand.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _button(Icons.add, 1, _value < WeightStepper.max),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final add in const [1, 5, 10])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: Brand.kraft,
                        backgroundColor: Brand.card,
                        side: BorderSide(
                          color: Brand.kraft.withValues(alpha: 0.5),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onPressed: () => _set(_value + add),
                      child: Text('+$add kg'),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Guide: 1 sako of PET bottles ≈ 3 kg · 1 sako of bote ≈ 15 kg',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Brand.inkSoft),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── barangay ─────────────────────────────

/// Field that opens a searchable list of Tagum's barangays.
/// Barangays the user follows are listed first.
class BarangayField extends StatelessWidget {
  const BarangayField({
    super.key,
    required this.value,
    required this.followed,
    required this.onChanged,
  });

  final String? value;
  final List<String> followed;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final has = value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: has ? Brand.mint : Brand.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: has ? Brand.forest : Brand.line,
              width: has ? 2 : 1.5,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              final picked = await pickBarangay(
                context,
                selected: value,
                followed: followed,
              );
              if (picked != null) onChanged(picked);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: has ? Brand.forest : Brand.paper,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.holiday_village,
                      color: has ? Colors.white : Brand.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          has ? 'Barangay' : 'Choose barangay',
                          style: TextStyle(
                            fontSize: has ? 14 : 18,
                            color: Brand.inkSoft,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (has)
                          Text(
                            value!,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Brand.ink,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.search, color: Brand.inkSoft),
                ],
              ),
            ),
          ),
        ),
        // One-tap shortcuts for the barangays the user follows.
        if (followed.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in followed)
                ChoiceChip(
                  avatar: Icon(
                    Icons.star_rounded,
                    size: 18,
                    color: b == value ? Brand.forest : Brand.star,
                  ),
                  label: Text(b),
                  selected: b == value,
                  showCheckmark: false,
                  onSelected: (_) => onChanged(b),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

Future<String?> pickBarangay(
  BuildContext context, {
  String? selected,
  List<String> followed = const [],
  Set<String> alreadyAdded = const {},
  String title = 'Which barangay?',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _BarangaySheet(
        scroll: scroll,
        selected: selected,
        followed: followed,
        alreadyAdded: alreadyAdded,
        title: title,
      ),
    ),
  );
}

class _BarangaySheet extends StatefulWidget {
  const _BarangaySheet({
    required this.scroll,
    required this.selected,
    required this.followed,
    this.alreadyAdded = const {},
    this.title = 'Which barangay?',
  });
  final ScrollController scroll;
  final String? selected;
  final List<String> followed;

  /// Shown greyed out with "Added" and cannot be picked again.
  final Set<String> alreadyAdded;
  final String title;

  @override
  State<_BarangaySheet> createState() => _BarangaySheetState();
}

class _BarangaySheetState extends State<_BarangaySheet> {
  String _q = '';

  Widget _tile(String b, {bool star = false}) {
    final sel = b == widget.selected;
    if (widget.alreadyAdded.contains(b)) {
      return ListTile(
        minTileHeight: 58,
        enabled: false,
        leading: const Icon(Icons.check_circle, color: Brand.leaf),
        title: Text(
          b,
          style: const TextStyle(fontSize: 19, color: Brand.inkSoft),
        ),
        trailing: const Text(
          'Added',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Brand.leaf,
          ),
        ),
      );
    }
    return ListTile(
      minTileHeight: 58,
      leading: Icon(
        star ? Icons.star_rounded : Icons.location_on_outlined,
        color: star ? Brand.star : Brand.inkSoft,
      ),
      title: Text(
        b,
        style: TextStyle(
          fontSize: 19,
          fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
          color: Brand.ink,
        ),
      ),
      trailing: sel
          ? const Icon(Icons.check_circle, color: Brand.forest)
          : null,
      tileColor: sel ? Brand.mint : null,
      onTap: () => Navigator.pop(context, b),
    );
  }

  Widget _heading(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(
      t.toUpperCase(),
      style: const TextStyle(
        fontSize: 13,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w800,
        color: Brand.inkSoft,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final added = widget.alreadyAdded;
    // Already-added barangays are listed once, on top, and left out below.
    final all = tagumBarangays
        .where((b) => b.toLowerCase().contains(q) && !added.contains(b))
        .toList();
    final mine = q.isEmpty
        ? widget.followed.where((b) => !added.contains(b)).toList()
        : const <String>[];
    final done = q.isEmpty
        ? tagumBarangays.where(added.contains).toList()
        : const <String>[];
    return Column(
      children: [
        Text(
          widget.title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _q = v),
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search barangay',
            ),
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scroll,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            children: [
              if (done.isNotEmpty) ...[
                _heading('Already added'),
                for (final b in done) _tile(b),
                _heading('Add another'),
              ],
              if (mine.isNotEmpty) ...[
                _heading('Your barangays'),
                for (final b in mine) _tile(b, star: true),
                _heading('All of Tagum City'),
              ],
              for (final b in all) _tile(b),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    q.isEmpty
                        ? 'You already added every barangay.'
                        : 'No barangay matches that name.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, color: Brand.inkSoft),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
