import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_commons/at_commons.dart';
import 'package:at_auth/at_auth.dart';

class FileAtKeysIo extends BaseAtKeysIo {
  String? filePath;
  FileAtKeysIo(String this.filePath);

  @override
  FutureOr<AtKeys> read(String atSign) async {
    Map<String, dynamic> decodedAtKeysData = {};
    AtAuthRequest atAuthRequest = AtAuthRequest(atSign);
    if (filePath != null) {
      if (!File(filePath!).existsSync()) {
        throw AtException('provided keys file does not exist. Please check whether the file path ${filePath} is valid');
      }
      String atAuthData = await File(filePath!).readAsString();
      decodedAtKeysData = jsonDecode(atAuthData);
      decodedAtKeysData = await decodeAtKeys(decodedAtKeysData, passPhrase: atAuthRequest.passPhrase);
    } else {
      throw AtException('atKeys filePath is required to read from file');
    }
    return decryptAtKeysWithSelfEncKey(decodedAtKeysData, PkamAuthMode.keysFile);
  }

  @override
  Future write(String atSign, AtKeys atKeys) {
    if (filePath == null) {
      throw AtException('atKeys filePath is required to write to file');
    }
    String atKeysData = encryptAtKeysWithSelfEncKey(atKeys, PkamAuthMode.keysFile);
    return File(filePath!).writeAsString(atKeysData);
  }

  @override
  FutureOr<AtKeys> generateKeys(String atSign, {String? publicKeyId}) {
    return generateKeyPairs(PkamAuthMode.keysFile);
  }
}

class SimAtKeysIo extends BaseAtKeysIo {
  AtKeys? atKeys;
  Map<String, dynamic>? encryptedKeysMap;

  SimAtKeysIo({this.atKeys, this.encryptedKeysMap});

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
  Future write(String atSign, AtKeys atKeys) {
    // TODO: implement write
    /// how are sim keys written?
    return Future.value();
  }

  @override
  FutureOr<AtKeys> generateKeys(String atSign, {String? publicKeyId}) {
    if (publicKeyId == null || publicKeyId.isEmpty) {
      throw AtException('publicKeyId is required to generate keys when auth mode is sim');
    }
    return generateKeyPairs(PkamAuthMode.keysFile, publicKeyId: publicKeyId);
  }
}


