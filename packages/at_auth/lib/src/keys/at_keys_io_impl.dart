import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:meta/meta.dart';

import 'package:at_commons/at_commons.dart';
import 'package:at_cli_commons/at_cli_commons.dart'
    show getDefaultAtKeysFilePath, getHomeDirectory;
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
  Future<AtKeys> read(String atSign) async {
    Map<String, dynamic> decodedAtKeysData = {};
    String file = filePath!(atSign);
    if (!File(file).existsSync()) {
      throw AtException(
          'provided keys file does not exist. Please check whether the file path $file is valid');
    }
    String atAuthData = await File(file).readAsString();
    decodedAtKeysData = jsonDecode(atAuthData);
    decodedAtKeysData =
        await decodeAtKeys(decodedAtKeysData, passPhrase: passPhrase);
    return decryptAtKeysWithSelfEncKey(
        decodedAtKeysData, PkamAuthMode.keysFile);
  }

  @override
  Future write(String atSign, AtKeys atKeys) async {
    String atKeysData =
        await encryptAtKeysWithSelfEncKey(atKeys, PkamAuthMode.keysFile);
    return File(filePath!(atSign)).writeAsString(atKeysData);
  }
}

//TODO: future add simAtKeysIo
// class SimAtKeysIo extends GeneratedAtKeysIo with KeyIOMixin {
