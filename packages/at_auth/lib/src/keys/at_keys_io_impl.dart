import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:meta/meta.dart';

import 'package:at_commons/at_commons.dart';
import 'package:at_cli_commons/at_cli_commons.dart' show getDefaultAtKeysFilePath, getHomeDirectory;
import 'package:at_auth/src/auth/at_auth_request.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/at_keys_io.dart';

class FileAtKeysIo extends WrittenAtKeysIo with KeyIOMixin {
  @visibleForTesting
  String? filePath;
  FileAtKeysIo({this.filePath});

  @override
  FutureOr<AtKeys> read(String atSign) async {
    Map<String, dynamic> decodedAtKeysData = {};
    filePath ??= getDefaultAtKeysFilePath(getHomeDirectory()!, atSign);
    AtAuthRequest atAuthRequest = AtAuthRequest(atSign);
    if (filePath != null) {
      if (!File(filePath!).existsSync()) {
        throw AtException('provided keys file does not exist. Please check whether the file path $filePath is valid');
      }
      String atAuthData = await File(filePath!).readAsString();
      decodedAtKeysData = jsonDecode(atAuthData);
      decodedAtKeysData = await decodeAtKeys(decodedAtKeysData, passPhrase: atAuthRequest.passPhrase);
    } else {
      throw AtException('atKeys filePath is required to read from file');
    }
    return decryptAtKeysWithSelfEncKey(decodedAtKeysData, PkamAuthMode.keysFile);
  }

  //tbm to WrittenAtKeysIo ?
  @override
  Future write(String atSign, AtKeys atKeys) {
    filePath ??= getDefaultAtKeysFilePath(getHomeDirectory()!, atSign);
    String atKeysData = encryptAtKeysWithSelfEncKey(atKeys, PkamAuthMode.keysFile);
    return File(filePath!).writeAsString(atKeysData);
  }
}

class SimAtKeysIo extends GeneratedAtKeysIo with KeyIOMixin {
  AtKeys? atKeys;
  Map<String, dynamic>? encryptedKeysMap;
  //Map of atsigns to publicKeyIds 
  Map<String, String> publicKeyMap = {};

  SimAtKeysIo({this.atKeys, this.encryptedKeysMap, String? publicKeyId}) {
    if (publicKeyId != null) {
    
    }
  }

  @override
  FutureOr<AtKeys> read(String atSign) async {
    if (atKeys != null) {
      return atKeys!;
    }
    if (encryptedKeysMap != null) {
      encryptedKeysMap = await decodeAtKeys(encryptedKeysMap!);
      return decryptAtKeysWithSelfEncKey(encryptedKeysMap!, PkamAuthMode.sim);
    }

    throw AtAuthenticationException('atAuthKeys or encryptedKeysMap is required to read from keychain');
  }

  @override
  AtKeys generateKeys(String atSign) {
    if (publicKeyMap[atSign] == null) {
      throw AtAuthenticationException('publicKeyId is required in SimAtKeysIo.publicKeyMap to read pkam public key from sim/secure element');
    }
    return generateKeyPairs(atSign: atSign);
  }
}
