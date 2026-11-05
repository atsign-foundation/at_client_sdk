/// Every code sample the upgrade guide gives a Flutter app as its "after"
/// compiles against this package: those tagged `dart after`, which both
/// paths share, and `dart after-flutter`.
///
/// Catalogue: docs/upgrade-to-4.md
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The fenced samples in [guide] whose info string is `dart <tag>`.
List<String> samplesTagged(String guide, String tag) => [
  for (final m in RegExp(
    '^```dart $tag\\n(.*?)^```',
    multiLine: true,
    dotAll: true,
  ).allMatches(guide))
    m.group(1)!,
];

/// The guide leaves out the platform package's import, which every file needs.
const platformImport =
    "import 'package:at_client_flutter/at_client_flutter.dart';";

/// [sample] as the file an app would hold: with [platformImport].
String asFile(String sample) =>
    sample.contains(platformImport) ? sample : '$platformImport\n$sample';

/// `flutter analyze` over [samples], each its own library in a directory
/// inside this package, so they resolve against its dependencies.
ProcessResult analyze(List<String> samples, String dirName) {
  final dir = Directory('.dart_tool/$dirName');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  for (var i = 0; i < samples.length; i++) {
    File('${dir.path}/sample_$i.dart').writeAsStringSync(samples[i]);
  }
  try {
    return Process.runSync('flutter', [
      'analyze',
      '--no-pub',
      '--no-fatal-infos',
      dir.path,
    ]);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  final guide = File('../../docs/upgrade-to-4.md').readAsStringSync();

  test('every sample a Flutter app follows compiles', () {
    final shared = samplesTagged(guide, 'after');
    final flutterOnly = samplesTagged(guide, 'after-flutter');
    expect(shared, isNotEmpty, reason: 'the guide tags shared samples');
    expect(flutterOnly, isNotEmpty, reason: 'the guide tags Flutter samples');

    final result = analyze([
      for (final s in [...shared, ...flutterOnly]) asFile(s),
    ], 'upgrade_guide_flutter');
    expect(
      result.exitCode,
      0,
      reason: 'flutter analyze said:\n${result.stdout}${result.stderr}',
    );
  });

  test('a sample that does not compile is caught', () {
    final result = analyze([
      "$platformImport\nint notAnInt = 'a string';\n",
    ], 'upgrade_guide_control');
    expect(
      result.exitCode,
      isNot(0),
      reason: 'the harness must see an error, or a green above proves nothing',
    );
  });
}
