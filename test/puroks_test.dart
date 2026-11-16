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
  test('reads bullets, numbers, plain lines and tables', () {
    const md = '''
# Mankilam

- Purok Abaca
* Tadena
1. purok Capitol
2) **Magkidong**
Galingan
- Purok Abaca

| Purok | Leader |
|-------|--------|
| Lemonsito | x |
| Sitio Bautista | y |
''';
    expect(parsePurokMarkdown(md), [
      'Purok Abaca',
      'Purok Tadena',
      'Purok Capitol',
      'Purok Magkidong',
      'Purok Galingan',
      'Purok Lemonsito',
      'Sitio Bautista',
    ]);
  });

  test('numbered puroks keep their numbers', () {
    expect(parsePurokMarkdown('- Purok 1\n- 2\n- Purok 6-B'), [
      'Purok 1',
      'Purok 2',
      'Purok 6-B',
    ]);
  });

  test('empty or missing file falls back to Purok 1–20', () async {
    final d = await PurokDirectory.load(
      _FakeBundle({'mankilam.md': '- Abaca\n- Tadena', 'apokon.md': ''}),
    );
    expect(d.puroksOf('Mankilam'), ['Purok Abaca', 'Purok Tadena']);
    expect(d.hasList('Mankilam'), isTrue);
    // Empty file.
    expect(d.hasList('Apokon'), isFalse);
    expect(d.puroksOf('Apokon'), hasLength(20));
    expect(d.puroksOf('Apokon').first, 'Purok 1');
    // No file at all (e.g. Busaon).
    expect(d.puroksOf('Busaon').last, 'Purok 20');
  });
}
