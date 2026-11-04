import 'dart:io';

import 'package:test/test.dart';

/// Catalogue: features/at_client/web_safe.feature
void main() {
  test('No deprecation promises removal in 4.0', () {
    final annotation = RegExp(r'@Deprecated\(((?:[^()]|\([^()]*\))*)\)');
    final joined = RegExp(r"""['"]\s*\n\s*['"]""");
    final deprecations = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in annotation.allMatches(source)) {
        deprecations.add('${file.path}: ${match[1]!.replaceAll(joined, '')}');
      }
      for (final line in source.split('\n')) {
        if (line.trimLeft().startsWith('///') &&
            line.toLowerCase().contains('deprecat')) {
          deprecations.add('${file.path}: ${line.trim()}');
        }
      }
    }

    final promise = RegExp(r'4\.0|\bv4\b|next major', caseSensitive: false);
    expect(deprecations.where(promise.hasMatch), isEmpty,
        reason: 'a 4.0.0 release keeps nothing that promised to go in it');
    expect(deprecations.where((d) => d.contains('5.0.0')), isNotEmpty,
        reason: 'the control: the deprecations that name a major were read');
  });
}
