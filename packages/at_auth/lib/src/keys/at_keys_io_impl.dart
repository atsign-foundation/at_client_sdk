import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:at_auth/at_auth.dart';
import 'package:meta/meta.dart';

import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/at_keys_io.dart';

/// An implementation of [AtKeysIo] that reads and writes AtKeys to the file system.
/// This implementation uses a mixin [KeyIOMixin] to provide common functionality for encoding and decoding AtKeys.
/// The [FileAtKeysIo] class can be configured with an optional [filePath] and [passPhrase].
///
/// Optional Parameters:
/// If [filePath] is a format function derived from your atSign. Defaults to using %HOME%/.atsign/keys/$atsign_key.t atKeys
/// The [passPhrase] is used for atKeys files that are password protected.
class FileAtKeysIo extends WrittenAtKeysIo {
  @visibleForTesting
  String Function(String)? filePath;
  String? passPhrase;
  FileAtKeysIo({this.filePath, this.passPhrase}) {
    filePath ??=
        (atsign) => getDefaultAtKeysFilePath(getHomeDirectory()!, atsign);
  }

  /// Reads AtKeys from the file system.
  /// The [atSign] parameter is used to determine the file path if not provided during instantiation.
  /// The method returns a Future that resolves to an instance of [AtKeys].
  @override
  Future<AtKeys> read(String atSign,
      {IOSink? askPasswordSink, Stream<List<int>>? readPasswordStream}) async {
    Map<String, dynamic> decodedAtKeysData = {};
    String file = filePath!(atSign);

    if (!File(file).existsSync()) {
      throw AtException(
          'provided keys file does not exist. Please check whether the file path $file is valid');
    }

    String atAuthData = await File(file).readAsString();
    decodedAtKeysData = jsonDecode(atAuthData);
    try {
      decodedAtKeysData =
          await decodeAtKeys(decodedAtKeysData, passPhrase: passPhrase);
    } on AtPasswordRequiredException {
      // fallback: prompt for passphrase when not provided through args
      if (askPasswordSink == null || readPasswordStream == null) rethrow;

      askPasswordSink.write('Please provide passphrase for $filePath: ');
      final promptedPass = utf8.decode(await readPasswordStream.first);
      if (promptedPass.isNullOrEmpty) rethrow;

      decodedAtKeysData =
          await decodeAtKeys(decodedAtKeysData, passPhrase: passPhrase);
    }
    return decryptAtKeysWithSelfEncKey(
        decodedAtKeysData, PkamAuthMode.keysFile);
  }

  @override
  Future write(String atSign, AtKeys atKeys) async {
    String atKeysData =
        await encryptAtKeysWithSelfEncKey(atKeys, PkamAuthMode.keysFile);
    await File(filePath!(atSign)).writeAsString(atKeysData);
  }
}

// Taken from at_cli_commons, but I can't import it due to circular dependencies
// at_cli_commons depends on at_onboarding_cli....
String getDefaultAtKeysFilePath(String homeDirectory, String atSign) {
  return '$homeDirectory/.atsign/keys/${atSign}_key.atKeys'
      .replaceAll('/', Platform.pathSeparator);
}

String? getHomeDirectory({bool throwIfNull = false}) {
  String? homeDir;
  switch (Platform.operatingSystem) {
    case 'linux':
    case 'macos':
      homeDir = Platform.environment['HOME'];
      break;

    case 'windows':
      homeDir = Platform.environment['USERPROFILE'];
      break;

    case 'android':
      // Probably want internal storage.
      homeDir = '/storage/sdcard0';
      break;

    case 'ios':
    // iOS doesn't really have a home directory.
    case 'fuchsia':
    // I have no idea.
    default:
      homeDir = null;
  }
  if (throwIfNull && homeDir == null) {
    throw ('\nUnable to determine your home directory: please set environment variable\n\n');
  }
  return homeDir;
}
