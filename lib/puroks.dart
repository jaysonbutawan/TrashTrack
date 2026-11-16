// Puroks of each Tagum barangay, read from the Markdown files in the project
// root (one file per barangay, e.g. mankilam.md). A barangay whose file is
// missing or empty gets numbered puroks (Purok 1–20) instead.
//
// File format — one purok per line; any of these work:
//   # Mankilam            ← headings are ignored
//   - Purok Abaca         ← bullet
//   1. Tadena             ← numbered ("Purok " is added when missing)
//   | Purok Capitol | ... ← table: the first cell is used

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

/// Purok names from one barangay's Markdown file, in file order, without
/// duplicates. Empty when the file has no usable lines.
List<String> parsePurokMarkdown(String markdown) {
  final out = <String>[];
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
      // Header cells such as "Purok" or "Name".
      if (RegExp(
        r'^(purok|puroks|name|no\.?|#)$',
        caseSensitive: false,
      ).hasMatch(line)) {
        continue;
      }
    }
    line = line
        .replaceFirst(RegExp(r'^([-*+]|\d+[.)])\s+'), '') // list markers
        .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1') // [text](link)
        .replaceAll(RegExp(r'[*_`]'), '') // bold / italic / code
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (line.isEmpty) continue;
    final name =
        RegExp(r'^(purok|sitio)\b', caseSensitive: false).hasMatch(line)
        ? line.replaceFirstMapped(
            RegExp(r'^(purok|sitio)', caseSensitive: false),
            (m) => m[0]![0].toUpperCase() + m[0]!.substring(1).toLowerCase(),
          )
        : 'Purok $line';
    if (!out.contains(name)) out.add(name);
  }
  return out;
}

/// The purok choices for every barangay.
class PurokDirectory {
  const PurokDirectory(this._lists);

  /// No lists at all: every barangay gets numbered puroks.
  static const PurokDirectory empty = PurokDirectory({});

  final Map<String, List<String>> _lists;

  /// True when the barangay's own file has puroks (not the numbered default).
  bool hasList(String barangay) => _lists[barangay]?.isNotEmpty ?? false;

  List<String> puroksOf(String barangay) =>
      hasList(barangay) ? _lists[barangay]! : numberedPuroks();

  static Future<PurokDirectory>? _loading;

  /// Reads the Markdown files once; later calls reuse the result.
  static Future<PurokDirectory> load([AssetBundle? bundle]) =>
      _loading ??= _read(bundle ?? rootBundle);

  static Future<PurokDirectory> _read(AssetBundle bundle) async {
    final lists = <String, List<String>>{};
    for (final b in tagumBarangays) {
      final file = purokFiles[b];
      if (file == null) continue;
      try {
        lists[b] = parsePurokMarkdown(
          await bundle.loadString(file, cache: false),
        );
      } catch (_) {
        // Missing file → numbered default.
      }
    }
    return PurokDirectory(lists);
  }
}
