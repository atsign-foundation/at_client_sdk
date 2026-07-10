import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/passphrase_envelope.dart';
import 'package:at_auth/src/keys/types.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';

/// An implementation of [AtKeysIo] that reads and writes AtKeys to the file system.
/// This implementation still uses [KeyIOMixin] for encoding and decoding Legacy AtKeys.
/// The [FileAtKeysIo] class can be configured with an optional [filePath] and [passPhrase].
///
/// Optional Parameters:
/// [filePath] formats the file path from your atSign. Defaults to %HOME%/.atsign/keys/<atsign>_key.atKeys
/// The [passPhrase] is used for atKeys files that are password protected.
class FileAtKeysIo extends WrittenAtKeysIo {
  String Function(String)? filePath;
  String? passPhrase;
  FileAtKeysIo({this.filePath, this.passPhrase}) {
    filePath ??=
        (atsign) => getDefaultAtKeysFilePath(getHomeDirectory()!, atsign);
  }

  /// Reads AtKeys from the file system.
  /// The [atsign] parameter is used to determine the file path if not provided during instantiation.
  /// The method returns a Future that resolves to an instance of [AtKeys].
  @override
  Future<AtKeys> read(String atsign) async {
    String file = filePath!(atsign);
    if (!File(file).existsSync()) {
      throw AtException(
          'provided keys file does not exist. Please check whether the file path $file is valid');
    }
    String atAuthData = await File(file).readAsString();
    Map<String, dynamic> json = jsonDecode(atAuthData);
    if (passphraseCodec.isEnvelope(json)) {
      json = await passphraseCodec.decode(json, passPhrase: passPhrase);
    }
    if (!json.containsKey('version')) {
      return decryptAtKeysWithSelfEncKey(json, PkamAuthMode.keysFile);
    }
    return AtKeys.fromDocumentJson(json);
  }

  @override
  Future write(String atsign, AtKeys atKeys) async {
    String path = filePath!(atsign);
    if (!Directory(path).parent.existsSync()) {
      await Directory(path).parent.create(recursive: true);
    }
    //don't overwrite the file
    if (File(path).existsSync()) {
      throw AtKeysFileOverwriteException(
          'Tried writing $path, but failed since it already exists');
    }
    String plaintext;
    if (atKeys.keyMaterials.isEmpty) {
      plaintext = await encryptAtKeysWithSelfEncKey(
        atKeys,
        PkamAuthMode.keysFile,
        atsign,
      );
    } else {
      //todo: remove this line in v4, ensures we're writing new format
      atKeys.atsign ??= atsign.toAtsign();
      plaintext = jsonEncode(atKeys.toDocumentJson());
    }
    plaintext = await _encryptWithPassPhraseIfNeeded(plaintext);

    await File(path).writeAsString(plaintext);
  }

  @override
  FutureOr<void> append(Atsign atsign, AtKeysMaterial material) async {
    final path = filePath!(atsign);
    final originalText = await File(path).readAsString();
    Map<String, dynamic> fileJson = jsonDecode(originalText);
    if (passphraseCodec.isEnvelope(fileJson)) {
      fileJson = await passphraseCodec.decode(fileJson, passPhrase: passPhrase);
    }

    final AtKeys keys;
    final Map<String, dynamic> existingForAssurance;
    if (fileJson.containsKey('version')) {
      keys = AtKeys.fromDocumentJson(fileJson);
      existingForAssurance = fileJson;
    } else {
      // Legacy files may hold some fields self-encrypted; decrypt first so
      // assurance compares plaintext against plaintext, not ciphertext
      // against plaintext.
      keys = await decryptAtKeysWithSelfEncKey(fileJson, PkamAuthMode.keysFile)
        ..atsign = atsign;
      keys.metadata.addAll({
        for (final entry in fileJson.entries)
          if (!auth_constants.keySchemaList.contains(entry.key))
            entry.key: entry.value,
      });
      existingForAssurance = keys.toJson();
    }

    keys.addKey(material);
    final candidate = keys.toDocumentJson();

    assurance.validateMapUpdate(
      existing: existingForAssurance,
      candidate: candidate,
    );
    final plaintext =
        await _encryptWithPassPhraseIfNeeded(jsonEncode(candidate));
    await File(AtKeysAssurance.archiveNameFor(path))
        .writeAsString(originalText);
    await File(path).writeAsString(plaintext);
  }

  Future<String> _encryptWithPassPhraseIfNeeded(String plaintext) async {
    if (passPhrase == null || passPhrase!.isEmpty) {
      return plaintext;
    }
    final envelope = await AtKeysPassphraseCrypto.fromHashingAlgorithm(
            HashingAlgoType.argon2id)
        .encrypt(plaintext, passPhrase!);
    return envelope.toString();
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
