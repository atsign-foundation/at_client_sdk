import 'dart:io';

import 'package:at_auth/at_auth_io.dart';

/// Reads keys for the atSign in `args` through a `FileAtKeysIo` built with
/// no file path, so it reads from the default path under `HOME`.
Future<void> main(List<String> args) async {
  final atsign = args.single;
  final fileAtKeysIo = FileAtKeysIo();
  final atKeys = await fileAtKeysIo.read(atsign);
  if (atKeys.apkamPrivateKey == null ||
      atKeys.apkamPublicKey == null ||
      atKeys.apkamSymmetricKey == null ||
      atKeys.defaultEncryptionPrivateKey == null ||
      atKeys.defaultEncryptionPublicKey == null ||
      atKeys.defaultSelfEncryptionKey == null) {
    exit(1);
  }
}
