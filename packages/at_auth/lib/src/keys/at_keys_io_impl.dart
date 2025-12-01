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
/// If [filePath] is not provided, it defaults to a standard location based on the atSign.
/// The [passPhrase] is used for atKeys files that are password protected.
class FileAtKeysIo extends WrittenAtKeysIo {
  @visibleForTesting
  String? filePath;
  String? passPhrase;
  FileAtKeysIo({this.filePath, this.passPhrase});

  /// Reads AtKeys from the file system.
  /// The [atSign] parameter is used to determine the file path if not provided during instantiation.
  /// The method returns a Future that resolves to an instance of [AtKeys].
  @override
  Future<AtKeys> read(String atSign) async {
    filePath ??= getDefaultAtKeysFilePath(getHomeDirectory()!, atSign);
    if (filePath == null) {
      throw AtException('atKeys filePath is required to read from file');
    }
    if (!File(filePath!).existsSync()) {
      throw AtException(
          'provided keys file does not exist. Please check whether the file path $filePath is valid');
    }
    String atAuthData = await File(filePath!).readAsString();
    final jsonData = jsonDecode(atAuthData);
    Map<String, dynamic> decodedAtKeysData =
        await decodeAtKeys(jsonData, passPhrase: passPhrase);

    return decryptAtKeysWithSelfEncKey(
        decodedAtKeysData, PkamAuthMode.keysFile);
  }

  @override
  Future write(String atSign, AtKeys atKeys) async {
    filePath ??= getDefaultAtKeysFilePath(getHomeDirectory()!, atSign);
    String atKeysData =
        await encryptAtKeysWithSelfEncKey(atKeys, PkamAuthMode.keysFile);
    return File(filePath!).writeAsString(atKeysData);
  }
}

//TODO: future add simAtKeysIo
// class SimAtKeysIo extends GeneratedAtKeysIo with KeyIOMixin {
