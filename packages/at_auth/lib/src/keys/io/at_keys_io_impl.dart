import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/keys/serialization/document.dart';
import 'package:at_auth/src/keys/serialization/passphrase_envelope.dart';
import 'package:at_chops/at_chops.dart' hide AtKeysCrypto;
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';

/// An implementation of [AtKeysIo] that reads and writes AtKeys to the file system.
/// This implementation uses [AtKeysIoUtil] for encoding and decoding AtKeys.
/// The [FileAtKeysIo] class can be configured with an optional [filePath] and [passPhrase].
///
/// Optional Parameters:
/// If [filePath] is a format function derived from your atSign. Defaults to using %HOME%/.atsign/keys/$atsign_key.t atKeys
/// The [passPhrase] is used for atKeys files that are password protected.
class FileAtKeysIo extends WrittenAtKeysIo {
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
  Future<AtKeys> read(String atSign) async {
    String file = filePath!(atSign);
    if (!File(file).existsSync()) {
      throw AtException(
          'provided keys file does not exist. Please check whether the file path $file is valid');
    }
    String atAuthData = await File(file).readAsString();
    Map<String, dynamic> json = jsonDecode(atAuthData);
    if (passwordCodec.isEnvelope(json)) {
      json = await passwordCodec.decode(json, passPhrase: passPhrase);
    }
    AtKeysDocument document = codec.decodeDocument(json);
    return resolver.resolve(document);
  }

  @override
  Future write(String atSign, AtKeys atKeys) async {
    String path = filePath!(atSign);
    if (!Directory(path).parent.existsSync()) {
      await Directory(path).parent.create(recursive: true);
    }
    //don't overwrite the file
    if (File(path).existsSync()) {
      throw AtKeysFileOverwriteException(
          'Tried writing $path, but failed since it already exists');
    }

    final document = resolver.resolveToDocument(atKeys);
    final json = codec.encodeDocument(document);
    String plaintext = jsonEncode(json);
    if (passPhrase != null && passPhrase!.isNotEmpty) {
      PassphraseEnvelope envelope =
          await AtKeysCrypto.fromHashingAlgorithm(HashingAlgoType.argon2id)
              .encrypt(plaintext, passPhrase!);
      plaintext = envelope.toString();
    }

    await File(path).writeAsString(plaintext);
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
