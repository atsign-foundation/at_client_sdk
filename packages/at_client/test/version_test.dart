import 'dart:io';

import 'package:at_client/src/preference/at_client_config.dart';
import 'package:at_client/src/version.dart';
import 'package:test/test.dart';

void main() {
  final declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(File('pubspec.yaml').readAsStringSync())
      ?.group(1);

  test('version.dart matches the version in pubspec.yaml', () {
    expect(declared, isNotNull, reason: 'pubspec.yaml has no version line');
    expect(packageVersion, declared,
        reason: 'lib/src/version.dart is generated from pubspec.yaml; '
            'regenerate it with `dart run build_runner build`');
  });

  test('the version sent to the atServer is the pubspec version', () {
    expect(AtClientConfig.getInstance().atClientVersion, declared,
        reason: 'from: carries atClientVersion in its client config');
  });
}
