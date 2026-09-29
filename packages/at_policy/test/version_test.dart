import 'dart:io';

import 'package:at_policy/src/version.dart';
import 'package:test/test.dart';

void main() {
  test('version.dart matches the version in pubspec.yaml', () {
    final declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())
        ?.group(1);
    expect(declared, isNotNull, reason: 'pubspec.yaml has no version line');
    expect(packageVersion, declared,
        reason: 'lib/src/version.dart is generated from pubspec.yaml; '
            'regenerate it with `dart run build_runner build`');
  });
}
