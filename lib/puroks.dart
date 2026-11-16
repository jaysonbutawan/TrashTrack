// Puroks of each Tagum barangay, read from the Markdown files in the project
// root (one file per barangay, e.g. mankilam.md). A barangay whose file is
// missing, empty or says it has no record gets numbered puroks (Purok 1–20).
//
// File format — one purok per line:
//   • Purok Abaca                 ← bullet (•, -, *, + or "1.")
//   • CRS Subdivision             ← names are kept as written
//   • Purok 4 (Santol)            ← text in brackets becomes a hint
//   • Purok 8 / Purok 8-A         ← " / " lists several puroks on one line
//   • 6-B                         ← a bare number becomes "Purok 6-B"
//   # Mankilam                    ← headings are ignored
//   | Purok Capitol | ... |       ← table: the first cell is used

import 'package:flutter/services.dart';

import 'constants.dart';

/// Barangay → its Markdown file (as declared under `assets:` in pubspec).
const Map<String, String> purokFiles = {
  'Apokon': 'apokon.md',
  'Bincungan': 'bincungan.md',
  'Canocotan': 'canacotan.md',
  'Cuambogan': 'cuambogan.md',
  'La Filipina': 'lafilipina.md',
  'Liboganon': 'libuganon.md',
  'Madaum': 'madaum.md',
  'Magdum': 'magdum.md',
  'Magugpo East': 'magugpo-east.md',
  'Magugpo North': 'magugpo-north.md',
  'Magugpo South': 'magugpo-south.md',
  'Magugpo West': 'magugpo-west.md',
  'Mankilam': 'mankilam.md',
  'Nueva Fuerza': 'nuevafuerza.md',
  'Pagsabangan': 'pagsabangan.md',
  'San Miguel (Camp 4)': 'sanmiguel.md',
  'Visayan Village': 'Visayan-village.md',
};

/// How many numbered puroks to offer when a barangay has no list.
const int defaultPurokCount = 20;

List<String> numberedPuroks([int count = defaultPurokCount]) => [
  for (var n = 1; n <= count; n++) 'Purok $n',
];

/// One purok from a file: the name that is saved, plus an optional hint
/// shown under it ("Santol", "near La Filipina High School").
class PurokEntry {
  const PurokEntry(this.name, [this.note = '']);
  final String name;
  final String note;

  @override
  bool operator ==(Object other) =>
      other is PurokEntry && other.name == name && other.note == note;

  @override
  int get hashCode => Object.hash(name, note);

  @override
  String toString() => note.isEmpty ? name : '$name ($note)';
}

/// "I don't have a record", "none", "N/A" … — the file has no list.
final _noRecord = RegExp(
  r"^(n/?a|none|unknown|tba|tbd|wala\b.*|no (record|data|list)\b.*|"
  r"i (don'?t|do not) have\b.*)$",
  caseSensitive: false,
);

/// Purok entries from one barangay's Markdown file, in file order, without
/// duplicates. Empty when the file has no usable lines.
List<PurokEntry> parsePurokEntries(String markdown) {
  final out = <PurokEntry>[];
  final seen = <String>{};
  for (var line in markdown.split(RegExp(r'\r?\n'))) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('>')) continue;
    if (line.startsWith('|')) {
      // Table row: skip the |---| separator, take the first cell.
      if (RegExp(r'^\|[\s:|-]+\|?$').hasMatch(line)) continue;
      line = line
          .split('|')
          .map((c) => c.trim())
          .firstWhere((c) => c.isNotEmpty, orElse: () => '');
      if (RegExp(
        r'^(purok|puroks|name|no\.?|#)$',
        caseSensitive: false,
      ).hasMatch(line)) {
        continue; // header cell
      }
    }
    line = line
        .replaceFirst(RegExp(r'^([-*+•·–]|\d+[.)])\s*'), '') // list markers
        .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1') // [text](link)
        .replaceAll(RegExp(r'[*_`]'), '') // bold / italic / code
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (line.isEmpty || _noRecord.hasMatch(line)) continue;

    // Split off the hint in brackets (the last top-level "(...)").
    var note = '';
    final m = RegExp(r'^(.*?)\s*\(([^()]*)\)\s*$').firstMatch(line);
    if (m != null && m.group(1)!.isNotEmpty) {
      line = m.group(1)!;
      note = m.group(2)!.trim();
    }
    for (var name in line.split(RegExp(r'\s+/\s+'))) {
      name = name.replaceFirst(RegExp(r'[.,;:]+$'), '').trim();
      if (name.isEmpty) continue;
      // "6-B" or "12" alone means a numbered purok.
      if (RegExp(r'^\d+(-?[A-Za-z])?$').hasMatch(name)) name = 'Purok $name';
      // Same casing for the word itself: "purok abaca" → "Purok abaca".
      name = name.replaceFirstMapped(
        RegExp(r'^(purok|sitio)\b', caseSensitive: false),
        (x) => x[0]![0].toUpperCase() + x[0]!.substring(1).toLowerCase(),
      );
      if (seen.add(name.toLowerCase())) out.add(PurokEntry(name, note));
    }
  }
  return out;
}

/// Just the names, for places that do not show hints.
List<String> parsePurokMarkdown(String markdown) => [
  for (final e in parsePurokEntries(markdown)) e.name,
];

/// The purok choices for every barangay.
class PurokDirectory {
  const PurokDirectory(this._lists);

  /// No lists at all: every barangay gets numbered puroks.
  static const PurokDirectory empty = PurokDirectory({});

  final Map<String, List<PurokEntry>> _lists;

  /// True when the barangay's own file has puroks (not the numbered default).
  bool hasList(String barangay) => _lists[barangay]?.isNotEmpty ?? false;

  List<String> puroksOf(String barangay) => hasList(barangay)
      ? [for (final e in _lists[barangay]!) e.name]
      : numberedPuroks();

  /// Hint for one purok ("Santol"), or empty.
  String noteOf(String barangay, String purok) {
    for (final e in _lists[barangay] ?? const <PurokEntry>[]) {
      if (e.name == purok) return e.note;
    }
    return '';
  }

  static Future<PurokDirectory>? _loading;

  /// Reads the Markdown files once; later calls reuse the result.
  static Future<PurokDirectory> load([AssetBundle? bundle]) {
    if (bundle != null) return _read(bundle); // tests: no caching
    return _loading ??= _read(rootBundle);
  }

  static Future<PurokDirectory> _read(AssetBundle bundle) async {
    final lists = <String, List<PurokEntry>>{};
    for (final b in tagumBarangays) {
      final file = purokFiles[b];
      if (file == null) continue;
      try {
        lists[b] = parsePurokEntries(
          await bundle.loadString(file, cache: false),
        );
      } catch (_) {
        // Missing file → numbered default.
      }
    }
    return PurokDirectory(lists);
  }
}
