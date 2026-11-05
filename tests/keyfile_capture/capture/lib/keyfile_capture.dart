/// Writes a keyfile through the at_auth this package resolves, the way that
/// release's onboarding writes one, and records what it reads back.
library;

// The keyfile API both releases share is the one 3.3.0 marks deprecated.
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:at_auth/at_auth.dart';
import 'package:crypto/crypto.dart';

/// The atSign every fixture is written for: a test atSign.
const atsign = '@alice🛠';

/// The passphrase a passphrase-protected fixture is written under.
const fixturePassphrase = 'released-keyfile-fixture';

/// Writes `<name>.atKeys` into [outDir] and `<name>.read_back.json` beside
/// it, and returns the provenance entry for the pair.
///
/// The keys come from `generateKeyPairs`, the call the release's onboarding
/// makes, and the enrollment id is set before the write, as onboarding sets
/// the one its atServer issues. With [passphrase] the keyfile is written
/// under that passphrase.
Future<Map<String, Object?>> capture(
  String outDir,
  String name, {
  String? passphrase,
}) async {
  final keyfile = File('$outDir/$name.atKeys');
  if (keyfile.existsSync()) {
    throw StateError('${keyfile.path} already exists');
  }
  final io = FileAtKeysIo(
    filePath: (_) => keyfile.path,
    passPhrase: passphrase,
  );
  final keys = io.generateKeyPairs();
  keys.enrollmentId = _uuidV4();
  await io.write(atsign, keys);

  final back = await FileAtKeysIo(
    filePath: (_) => keyfile.path,
    passPhrase: passphrase,
  ).read(atsign);
  final readBack = <String, Object?>{
    'apkamPublicKey': back.apkamPublicKey?.toString(),
    'apkamPrivateKey': back.apkamPrivateKey?.toString(),
    'defaultEncryptionPublicKey': back.defaultEncryptionPublicKey?.toString(),
    'defaultEncryptionPrivateKey': back.defaultEncryptionPrivateKey?.toString(),
    'defaultSelfEncryptionKey': back.defaultSelfEncryptionKey?.toString(),
    'apkamSymmetricKey': back.apkamSymmetricKey?.toString(),
    'enrollmentId': back.enrollmentId,
    'metadata': back.metadata,
  };
  final readBackFile = File('$outDir/$name.read_back.json')
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(readBack)}\n',
    );

  return {
    'keyfile': _fileEntry(keyfile),
    'readBack': _fileEntry(readBackFile),
    'passphrase': passphrase,
  };
}

/// Captures every fixture an arm writes into [outDir], plus `provenance.json`.
///
/// [passphrase] adds a passphrase-protected keyfile beside the plain one.
Future<void> captureAll(List<String> args, {required bool passphrase}) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run bin/capture.dart <empty output directory>');
    exit(2);
  }
  final outDir = Directory(args.single);
  if (outDir.existsSync() && outDir.listSync().isNotEmpty) {
    throw StateError('${outDir.path} is not empty');
  }
  outDir.createSync(recursive: true);

  final lock = File('pubspec.lock');
  final atAuth = _lockedPackage(lock.readAsStringSync(), 'at_auth');
  final fixtures = [
    await capture(outDir.path, 'alice_key'),
    if (passphrase)
      await capture(
        outDir.path,
        'alice_key_passphrase',
        passphrase: fixturePassphrase,
      ),
  ];
  final provenance = {
    'writer': {
      'package': 'at_auth',
      'version': atAuth.version,
      'archiveSha256': atAuth.sha256,
    },
    'lockfile': {
      'path': 'tests/keyfile_capture/released/${atAuth.version}/pubspec.lock',
      'sha256': _sha256(lock),
    },
    'dart': Platform.version,
    'command': 'cd tests/keyfile_capture/released/${atAuth.version} && '
        'dart pub get && dart run bin/capture.dart <empty output directory>',
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
    'atsign': atsign,
    'fixtures': fixtures,
  };
  File('${outDir.path}/provenance.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(provenance)}\n',
  );
}

Map<String, Object?> _fileEntry(File file) => {
      'name': file.uri.pathSegments.last,
      'sha256': _sha256(file),
    };

String _sha256(File file) => sha256.convert(file.readAsBytesSync()).toString();

({String version, String sha256}) _lockedPackage(String lock, String name) {
  final entry = RegExp(
    '^  $name:\\n((?:    .*\\n)+)',
    multiLine: true,
  ).firstMatch(lock);
  if (entry == null) throw StateError('$name is not in pubspec.lock');
  String field(String key) =>
      RegExp('$key: "?([^"\\n]+)"?').firstMatch(entry.group(1)!)!.group(1)!;
  return (version: field('version'), sha256: field('sha256'));
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
