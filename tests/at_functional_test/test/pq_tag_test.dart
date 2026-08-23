/// Guards the `pq` tag set in this pack.
///
/// `dart_test.yaml` here declares the tag but deliberately carries no `paths:`
/// allowlist, so — unlike `tests/at_end2end_test` — an untagged file still
/// runs. What it does not do is appear in `--tags pq`, and that is the failure
/// this file exists to catch: the acceptance suite's stage and matrix arms
/// select on that tag, so a post-quantum test that nobody tagged is invisible
/// to them while looking perfectly healthy in a full run.
///
/// The set is *derived*, not listed, so it cannot drift: a file exercising a
/// post-quantum mechanism must carry `@Tags(['pq'])`, and a file exercising
/// none must not. Adding a PQ test therefore turns this red until it is
/// tagged, which is the whole point.
///
/// Pure local file inspection; it talks to no atServer.
library;

import 'dart:io';

import 'package:test/test.dart';

/// Symbols that mean "this file drives a post-quantum mechanism".
///
/// Deliberately the vocabulary of the mechanisms rather than of the file
/// names: `pq_*` naming is a convention nobody enforces, and the two files
/// that most needed the tag (`copied_keyfile_test`, `crypto_era_default_test`)
/// carry no `pq` in their names at all.
final _pqSymbols = RegExp(r'PqPosture|nskey|Nskey|pqSeal|pqOpen|'
    r'SigningAlgoType|keyPackage|KeyPackage|__ssenv|_apsk|'
    r'AtClientSecretSharing|signingRoot|SigningRoot|mldsa|enroll:');

bool _drivesPq(String source) => _pqSymbols.hasMatch(source);

/// Whether `@Tags(['pq'])` will actually be *applied* by the runner.
///
/// ⚠️ **Presence is not enough, and the difference is invisible.** A file-level
/// annotation only reaches the library when it sits **before** the `library;`
/// directive. Put it after, and it legally attaches to the next import
/// instead: `dart analyze` stays clean, the string is right there in the file,
/// and `--tags pq` silently does not select it. Measured 2026-08-23 — moving
/// one tag below `library;` turned that file's selection into "No tests match
/// the requested tag selectors" with nothing else going red.
///
/// So this checks placement, not presence: the tag line must exist, a
/// `library;` line must exist, and the tag must come first.
bool _isTagged(String source) {
  final lines = source.split('\n');
  final tag = lines.indexWhere((l) => RegExp(r"^@Tags\(\s*\[[^\]]*'pq'").hasMatch(l));
  final lib = lines.indexWhere((l) => l.trim() == 'library;');
  return tag >= 0 && lib >= 0 && tag < lib;
}

void main() {
  final dir = Directory('test');
  late List<File> files;

  setUpAll(() {
    expect(dir.existsSync(), isTrue,
        reason: 'cwd is ${Directory.current.path}; `dart test` runs from the '
            'package root, so test/ must be readable from here');
    files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))
        .where((f) => !f.path.endsWith('pq_tag_test.dart'))
        .toList();
    expect(files, isNotEmpty,
        reason: 'no *_test.dart found, so this guard is checking nothing');
  });

  // Both controls, drawn from the corpus rather than invented: without them a
  // broken matcher and a genuinely clean pack print the same nothing.
  test('the matcher discriminates on real files in this pack', () {
    final positive = File('test/nskey_data_path_live_test.dart');
    final negative = File('test/atclient_put_test.dart');
    expect(positive.existsSync() && negative.existsSync(), isTrue,
        reason: 'both control files must exist, or this proves nothing');
    expect(_drivesPq(positive.readAsStringSync()), isTrue,
        reason: 'nskey_data_path_live_test.dart drives the nskey data path, so '
            'a matcher that does not flag it is broken, not the pack');
    expect(_drivesPq(negative.readAsStringSync()), isFalse,
        reason: 'atclient_put_test.dart drives no PQ mechanism, so a matcher '
            'that flags it would tag the whole pack and mean nothing');
  });

  test('the placement check rejects a tag the runner would ignore', () {
    // The exact shape that fooled a presence-only check: the annotation is
    // present, spelled correctly, and attaches to the import rather than the
    // library. If this ever passes, _isTagged has gone back to grepping.
    const misplaced = "// a comment\nlibrary;\n@Tags(['pq'])\nimport 'x.dart';";
    const correct = "// a comment\n@Tags(['pq'])\nlibrary;\nimport 'x.dart';";
    expect(_isTagged(misplaced), isFalse,
        reason: 'a tag below `library;` attaches to the import and never '
            'reaches the library, so --tags pq does not select the file');
    expect(_isTagged(correct), isTrue,
        reason: 'the canonical placement must still count, or this guard '
            'would demand every file be retagged');
  });

  test('every file driving a PQ mechanism carries the pq tag', () {
    final untagged = files
        .where((f) => _drivesPq(f.readAsStringSync()))
        .where((f) => !_isTagged(f.readAsStringSync()))
        .map((f) => f.uri.pathSegments.last)
        .toList()
      ..sort();

    expect(untagged, isEmpty,
        reason: 'these files drive a post-quantum mechanism and carry no '
            "@Tags(['pq']), so `dart test --tags pq` does not select them and "
            'the acceptance suite\'s stage and matrix arms cannot see them. '
            "Add @Tags(['pq']) above `library;`: $untagged");
  });

  test('no file carries the pq tag without driving a PQ mechanism', () {
    final overTagged = files
        .where((f) => _isTagged(f.readAsStringSync()))
        .where((f) => !_drivesPq(f.readAsStringSync()))
        .map((f) => f.uri.pathSegments.last)
        .toList()
      ..sort();

    expect(overTagged, isEmpty,
        reason: 'these files carry the pq tag but drive no PQ mechanism this '
            'guard recognises. Either the tag is wrong, or the mechanism is '
            'new and _pqSymbols needs it — decide which, because a tag set '
            'that grows without a reason stops selecting anything: '
            '$overTagged');
  });
}
