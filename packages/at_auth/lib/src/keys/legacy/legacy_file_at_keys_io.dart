import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/keys/at_keys_document.dart';
import 'package:at_auth/src/keys/legacy/at_keys.dart';
import 'package:at_commons/at_commons.dart';

class LegacyFileAtKeysIo extends WrittenAtKeysIo {
  String Function(String)? filePath;
  String? passPhrase;
  LegacyFileAtKeysIo({this.filePath, this.passPhrase}) {
    filePath ??=
        (atsign) => getDefaultAtKeysFilePath(getHomeDirectory()!, atsign);
  }

  /// Reads AtKeys from the file system.
  /// The [atsign] parameter is used to determine the file path if not provided during instantiation.
  /// The method returns a Future that resolves to an instance of [AtKeys].
  @override
  FutureOr<AtKeysSet> read(String atsign, {AtKeysReadOptions? options}) async {
    Map<String, dynamic> decodedAtKeysData = {};
    String file = filePath!(atsign);
    if (!File(file).existsSync()) {
      throw AtException(
          'provided keys file does not exist. Please check whether the file path $file is valid');
    }
    String atAuthData = await File(file).readAsString();
    decodedAtKeysData = jsonDecode(atAuthData);
    decodedAtKeysData = await LegacyKeyIOUtil.decodeAtKeys(decodedAtKeysData,
        passPhrase: passPhrase);
    LegacyAtKeys atKeys = await LegacyKeyIOUtil.decryptAtKeysWithSelfEncKey(
        decodedAtKeysData, PkamAuthMode.keysFile);
    AtKeysDocument document = legacyAtKeysAdapter.toDocument(atsign, atKeys);
    return resolver.resolve(document);
  }

  @override
  Future<void> write(
    AtKeysSet atKeysSet, {
    AtKeysWriteOptions? options,
  }) async {
    String path = filePath!(atKeysSet.atsign);
    if (!Directory(path).parent.existsSync()) {
      await Directory(path).parent.create(recursive: true);
    }
    //don't overwrite the file
    if (File(path).existsSync()) {
      throw AtKeysFileOverwriteException(
          'Tried writing $path, but failed since it already exists');
    }
    var document = resolver.resolveToDocument(atKeysSet);
    var map = codec.encodeDocument(document);
    await File(path).writeAsString(jsonEncode(map));
  }

  @override
  Future<void> update(AtKeysSet atKeysSet) async {
    String path = filePath!(atKeysSet.atsign);
    if (!File(path).existsSync()) {
      throw AtException(
          'provided keys file does not exist. Please check whether the file path $path is valid');
    }
    var document = resolver.resolveToDocument(atKeysSet);
    var map = codec.encodeDocument(document);
    await File(path).writeAsString(jsonEncode(map));
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
