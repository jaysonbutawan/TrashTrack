import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/puroks.dart';

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files);
  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw StateError('missing $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads the bullet format of the barangay files', () {
    const md = '''
• Purok Abaca
• CRS Subdivision
• Purok 1.
• Purok 4 (Santol)
• Purok 8 / Purok 8-A
• Purok 5 / Purok 5-A (North Eagle 4 / Ilonggo Village Pag-asa)
• Purok 6 (Barrio/Center)
• Purok Pag-ibig 1 & 2
• Jalandoni
• purok abaca''';
    expect(parsePurokEntries(md), const [
      PurokEntry('Purok Abaca'),
      PurokEntry('CRS Subdivision'),
      PurokEntry('Purok 1'),
      PurokEntry('Purok 4', 'Santol'),
      PurokEntry('Purok 8'),
      PurokEntry('Purok 8-A'),
      PurokEntry('Purok 5', 'North Eagle 4 / Ilonggo Village Pag-asa'),
      PurokEntry('Purok 5-A', 'North Eagle 4 / Ilonggo Village Pag-asa'),
      PurokEntry('Purok 6', 'Barrio/Center'),
      PurokEntry('Purok Pag-ibig 1 & 2'),
      PurokEntry('Jalandoni'),
    ]);
  });

  test('other list styles and bare numbers', () {
    expect(
      parsePurokMarkdown(
        '# Apokon\n- Purok 2\n* 6-B\n1. Tadena\n| Purok |\n'
        '|---|\n| Capitol |',
      ),
      ['Purok 2', 'Purok 6-B', 'Tadena', 'Capitol'],
    );
  });

  test('"I don\'t have a record" counts as no list', () {
    expect(parsePurokMarkdown("I don't have a record"), isEmpty);
    expect(parsePurokMarkdown('N/A'), isEmpty);
  });

  test('empty or missing file falls back to Purok 1–20', () async {
    final d = await PurokDirectory.load(
      _FakeBundle({
        'mankilam.md': '• Purok Abaca\n• Purok 4 (Santol)',
        'apokon.md': '',
        'nuevafuerza.md': "I don't have a record",
      }),
    );
    expect(d.puroksOf('Mankilam'), ['Purok Abaca', 'Purok 4']);
    expect(d.noteOf('Mankilam', 'Purok 4'), 'Santol');
    expect(d.hasList('Apokon'), isFalse);
    expect(d.puroksOf('Apokon'), hasLength(20));
    expect(d.puroksOf('Nueva Fuerza').first, 'Purok 1');
    // No file at all (e.g. Busaon).
    expect(d.puroksOf('Busaon').last, 'Purok 20');
  });

  test('the real barangay files are bundled with the app', () async {
    final d = await PurokDirectory.load();
    expect(d.puroksOf('Mankilam'), contains('Purok Abaca'));
    expect(d.puroksOf('Visayan Village'), contains('Jalandoni'));
    expect(d.noteOf('La Filipina', 'Purok 4'), 'Santol');
    expect(d.hasList('Nueva Fuerza'), isFalse); // "I don't have a record"
    expect(d.hasList('Busaon'), isFalse); // no file yet
  });
}
