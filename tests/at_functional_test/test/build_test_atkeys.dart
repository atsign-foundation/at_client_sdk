// One-shot helper: build .atKeys files for the virtualenv test atSigns
// (@alice🛠, @bob🛠) by encrypting the raw keys from `at_demo_data`
// with each atSign's self-encryption key, in the same on-wire format
// `FileAtKeysIo.write` produces.
//
// Usage:
//   cd tests/at_functional_test
//   dart run test/build_test_atkeys.dart [output-dir]
//
// Output files:
//   <output-dir>/@alice🛠_key.atKeys
//   <output-dir>/@bob🛠_key.atKeys
//
// Default output-dir is `test/testData/` (same place the rest of the
// functional-test fixtures live). Then point the dockerstats CLIs at
// those files via the -k flag, e.g.:
//
//   dart run bin/dockerstats_publish.dart \
//       -a '@alice🛠' -k path/to/@alice🛠_key.atKeys ...
//
// This avoids polluting ~/.atsign/keys/ with virtualenv-only keys.

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_chops/at_chops.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;

const _atSigns = ['@alice🛠', '@bob🛠'];

Future<void> main(List<String> args) async {
  final outDir = args.isNotEmpty ? args[0] : 'test/testData';
  await Directory(outDir).create(recursive: true);

  for (final atSign in _atSigns) {
    final selfEncKey = demo.aesKeyMap[atSign];
    final encPub = demo.encryptionPublicKeyMap[atSign];
    final encPriv = demo.encryptionPrivateKeyMap[atSign];
    final pkamPub = demo.pkamPublicKeyMap[atSign];
    final pkamPriv = demo.pkamPrivateKeyMap[atSign];
    if (selfEncKey == null ||
        encPub == null ||
        encPriv == null ||
        pkamPub == null ||
        pkamPriv == null) {
      stderr.writeln('demo data missing for $atSign — aborting');
      exit(1);
    }

    // Encrypt each long key with the atSign's selfEncryptionKey, using
    // the legacy IV so the resulting file is interchangeable with
    // anything FileAtKeysIo.read consumes.
    final atChops =
        AtChopsImpl(AtChopsKeys()..selfEncryptionKey = AESKey(selfEncKey));
    final iv = AtChopsUtil.generateIVLegacy();
    Future<String> enc(String plaintext) async =>
        (await atChops.encryptString(plaintext, EncryptionKeyType.aes256,
                keyName: 'selfEncryptionKey', iv: iv))
            .result;

    final atKeysJson = <String, dynamic>{
      auth_constants.defaultEncryptionPublicKey: await enc(encPub),
      auth_constants.defaultEncryptionPrivateKey: await enc(encPriv),
      auth_constants.apkamPublicKey: await enc(pkamPub),
      auth_constants.apkamPrivateKey: await enc(pkamPriv),
      auth_constants.defaultSelfEncryptionKey: selfEncKey,
      // The wrapping schema versioning + atSign label are not strictly
      // required by FileAtKeysIo.read (it only consumes the entries
      // above) but we include them to match what the onboarding CLI
      // produces — so the file looks identical to a fresh-onboarded
      // file under inspection.
      '@$atSign': '',
    };

    final outPath = '$outDir/${atSign}_key.atKeys';
    final outFile = File(outPath);
    await outFile.writeAsString(jsonEncode(atKeysJson));
    stdout.writeln('wrote $outPath');
  }
  stdout.writeln('done');
}
