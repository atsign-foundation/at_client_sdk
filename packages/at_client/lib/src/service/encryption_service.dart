import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/converters/encryption/aes_converter.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';

class EncryptionService {
  RemoteSecondary? remoteSecondary;

  LocalSecondary? localSecondary;

  late final String atSign;

  late final AtSignLogger logger;

  @experimental
  AtTelemetryService? telemetry;

  EncryptionService(this.atSign) {
    logger = AtSignLogger('EncryptionService ($atSign)');
  }

  Future<List<int>> encryptStream(List<int> value, String sharedWith,
      {String? ivBase64}) async {
    return EncryptionUtil.encryptBytes(
        value, await _getAESKeyForEncryption(sharedWith),
        ivBase64: ivBase64);
  }

  Future<String> _getAESKeyForEncryption(String sharedWith) async {
    bool isSharedKeyInLocal = false;
    var sharedKey = await _getSharedKeyFromLocalForEncryption(sharedWith);
    if (sharedKey != null && sharedKey.isNotEmpty && sharedKey != 'data:null') {
      isSharedKeyInLocal = true;
    }
    // If sharedKey is not found in localSecondary, search in remote secondary.
    if (!isSharedKeyInLocal) {
      try {
        sharedKey = await _getSharedKeyFromRemoteForEncryption(sharedWith);
      } on AtClientException {
        logger.finer(
            'shared key for $sharedWith not found in remote secondary. Generating a new shared key');
      }
    }
    // If sharedKey is not found in localSecondary, search in remote secondary.
    if (!isSharedKeyInLocal) {
      try {
        sharedKey = await _getSharedKeyFromRemoteForEncryption(sharedWith);
      } on AtClientException {
        logger.finer(
            'shared key for $sharedWith not found in remote secondary. Generating a new shared key');
      }
    }

    if (sharedKey == null || sharedKey == 'data:null') {
      logger.finer('Generated a new AES Key for $sharedWith');
      sharedKey = EncryptionUtil.generateAESKey();
    } else {
      sharedKey = sharedKey.replaceFirst('data:', '');
      var currentAtSignPrivateKey =
          await localSecondary!.getEncryptionPrivateKey();
      sharedKey =
          // ignore: deprecated_member_use_from_same_package
          EncryptionUtil.decryptKey(sharedKey, currentAtSignPrivateKey!);
    }

    // e.g save @bob:shared_key@alice
    await _saveSharedKey(sharedWith, sharedKey);
    // e.g save shared_key.bob@alice
    if (!isSharedKeyInLocal) {
      await _saveSharedKeyInLocal(sharedKey, sharedWith);
    }
    return sharedKey;
  }

  List<int> decryptStream(List<int> encryptedValue, String sharedKey,
      {String? ivBase64}) {
    //decrypt stream using decrypted aes shared key
    var decryptedValue = EncryptionUtil.decryptBytes(encryptedValue, sharedKey,
        ivBase64: ivBase64);
    return decryptedValue;
  }

  /// Returns sharedWith atSign publicKey.
  /// Throws [KeyNotFoundException] if sharedWith atSign publicKey is not found.
  Future<String?> _getSharedWithPublicKey(String sharedWithUser) async {
    //a local lookup the cached public key of sharedWith atsign.
    String? sharedWithPublicKey;
    var cachedPublicKeyBuilder = LLookupVerbBuilder()
      ..atKey = 'publickey.$sharedWithUser'
      ..sharedBy = atSign;
    try {
      sharedWithPublicKey =
          await localSecondary!.executeVerb(cachedPublicKeyBuilder);
    } on KeyNotFoundException {
      logger.finer(
          '${cachedPublicKeyBuilder.atKey}@$atSign not found in local secondary. Fetching from cloud secondary');
    }
    if (sharedWithPublicKey != null && sharedWithPublicKey != 'data:null') {
      sharedWithPublicKey =
          sharedWithPublicKey.toString().replaceAll('data:', '');
      return sharedWithPublicKey;
    }

    //b Lookup public key of sharedWith atsign
    var plookupBuilder = PLookupVerbBuilder()
      ..atKey = 'publickey'
      ..sharedBy = sharedWithUser;
    sharedWithPublicKey = await remoteSecondary!.executeVerb(plookupBuilder);
    sharedWithPublicKey =
        DefaultResponseParser().parse(sharedWithPublicKey).response;

    // If SharedWith PublicKey is not found throw KeyNotFoundException.
    if (sharedWithPublicKey == 'null' || sharedWithPublicKey.isEmpty) {
      throw KeyNotFoundException(
          'public key not found. data sharing is forbidden.');
    }
    //Cache the sharedWithPublicKey
    var sharedWithPublicKeyBuilder = UpdateVerbBuilder()
      ..atKey = 'publickey.$sharedWithUser'
      ..sharedBy = atSign
      ..value = sharedWithPublicKey;
    await localSecondary!.executeVerb(sharedWithPublicKeyBuilder, sync: true);
    return sharedWithPublicKey;
  }

  Future<String?> _getSharedKeyFromLocalForEncryption(String sharedWith) async {
    final sharedWithUser = sharedWith.replaceFirst('@', '');
    final llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = '${AtConstants.atEncryptionSharedKey}.$sharedWithUser'
      ..sharedBy = atSign;
    String? sharedKey;
    try {
      sharedKey = await localSecondary!.executeVerb(llookupVerbBuilder);
    } on KeyNotFoundException {
      logger.finer(
          '${llookupVerbBuilder.atKey}$atSign not found in local secondary. Fetching from cloud secondary.');
    }
    return sharedKey;
  }

  Future<String?> _getSharedKeyFromRemoteForEncryption(
      String sharedWith) async {
    final sharedWithUser = sharedWith.replaceFirst('@', '');
    final llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = '${AtConstants.atEncryptionSharedKey}.$sharedWithUser'
      ..sharedBy = atSign;
    String? sharedKey;
    try {
      sharedKey = await remoteSecondary!.executeVerb(llookupVerbBuilder);
    } on AtClientException {
      rethrow;
    }
    return sharedKey;
  }

  Future<void> _saveSharedKey(String sharedWith, String sharedKey) async {
    var sharedWithUser = sharedWith.replaceFirst('@', '');
    //Verify if encryptedSharedKey for sharedWith atSign is available.
    var lookupEncryptionSharedKey = LLookupVerbBuilder()
      ..sharedWith = sharedWith
      ..sharedBy = atSign
      ..atKey = AtConstants.atEncryptionSharedKey;
    String? result;
    try {
      result = await localSecondary!.executeVerb(lookupEncryptionSharedKey);
    } on KeyNotFoundException {
      logger.finer(
          '$sharedWith:${AtConstants.atEncryptionSharedKey}@$atSign not found in local secondary. Fetching from cloud secondary');
    }

    // Create the encryptedSharedKey if
    // a. encryptedSharedKey not available (or)
    // b. If the sharedKey is changed.
    if (result == null || result == 'data:null') {
      // ignore: prefer_typing_uninitialized_variables
      var sharedWithPublicKey;
      try {
        sharedWithPublicKey = await _getSharedWithPublicKey(sharedWithUser);
      } on KeyNotFoundException {
        rethrow;
      } on AtClientException {
        rethrow;
      }
      //Encrypt shared key with public key of sharedWith atsign.
      var encryptedSharedKey =
          EncryptionUtil.encryptKey(sharedKey, sharedWithPublicKey);
      // Store the encryptedSharedWith Key. Set ttr to enable sharedWith atsign to cache the encryptedSharedKey.
      var updateSharedKeyBuilder = UpdateVerbBuilder()
        ..sharedWith = sharedWith
        ..sharedBy = atSign
        ..atKey = AtConstants.atEncryptionSharedKey
        ..value = encryptedSharedKey
        ..ttr = 3888000;
      await localSecondary!.executeVerb(updateSharedKeyBuilder, sync: true);
    }
  }

  Future<void> _saveSharedKeyInLocal(
      String sharedKey, String sharedWith) async {
    var sharedWithUser = sharedWith.replaceFirst('@', '');
    // Store the sharedKey for future retrieval.
    // Encrypt the sharedKey with currentAtSign Public key and store it.
    var currentAtSignPublicKey =
        await localSecondary!.getEncryptionPublicKey(atSign);
    var encryptedSharedKeyForCurrentAtSign =
        EncryptionUtil.encryptKey(sharedKey, currentAtSignPublicKey!);

    var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
      ..sharedBy = atSign
      ..atKey = '${AtConstants.atEncryptionSharedKey}.$sharedWithUser'
      ..value = encryptedSharedKeyForCurrentAtSign;
    await localSecondary!
        .executeVerb(updateSharedKeyForCurrentAtSignBuilder, sync: true);
  }

  Future<String?> _getSharedKeyForDecryption(String sharedBy) async {
    String? encryptedSharedKey;
    var localLookupSharedKeyBuilder = LLookupVerbBuilder()
      ..isCached = true
      ..sharedBy = sharedBy
      ..sharedWith = atSign
      ..atKey = AtConstants.atEncryptionSharedKey;
    try {
      encryptedSharedKey =
          await localSecondary!.executeVerb(localLookupSharedKeyBuilder);
    } on KeyNotFoundException {
      logger.finer(
          '$sharedBy:${localLookupSharedKeyBuilder.atKey}@$atSign not found in local secondary. Fetching from cloud secondary');
    }
    if (encryptedSharedKey == null || encryptedSharedKey == 'data:null') {
      var sharedKeyLookUpBuilder = LookupVerbBuilder()
        ..atKey = AtConstants.atEncryptionSharedKey
        ..sharedBy = sharedBy
        ..auth = true;
      encryptedSharedKey =
          await remoteSecondary!.executeVerb(sharedKeyLookUpBuilder);
      encryptedSharedKey =
          DefaultResponseParser().parse(encryptedSharedKey).response;
    }
    if (encryptedSharedKey.isNotEmpty) {
      encryptedSharedKey = encryptedSharedKey.replaceFirst('data:', '');
    }
    if (encryptedSharedKey == 'null' || encryptedSharedKey.isEmpty) {
      throw KeyNotFoundException('encrypted Shared key not found');
    }

    //2. decrypt shared key using private key
    var currentAtSignPrivateKey =
        await (localSecondary!.getEncryptionPrivateKey());
    if (currentAtSignPrivateKey == null) {
      throw KeyNotFoundException('encryption private not found');
    }
    var sharedKey =
        // ignore: deprecated_member_use_from_same_package
        EncryptionUtil.decryptKey(encryptedSharedKey, currentAtSignPrivateKey);
    return sharedKey;
  }

  /// Used in StreamNotificationHandler.
  Future<String> getSharedKeyForDecryption(String sharedBy) async {
    sharedBy = sharedBy.replaceFirst('@', '');

    var encryptedSharedKey = await _getSharedKeyForDecryption(sharedBy);
    if (encryptedSharedKey == null || encryptedSharedKey == 'null') {
      throw KeyNotFoundException('encrypted Shared key not found');
    }
    //2. decrypt shared key using private key
    var currentAtSignPrivateKey =
        await (localSecondary!.getEncryptionPrivateKey());
    if (currentAtSignPrivateKey == null) {
      throw KeyNotFoundException('private encryption key not found');
    }
    var sharedKey =
        // ignore: deprecated_member_use_from_same_package
        EncryptionUtil.decryptKey(encryptedSharedKey, currentAtSignPrivateKey);
    return sharedKey;
  }

  /// Used in atmosphere pro
  String generateFileEncryptionKey() {
    return EncryptionUtil.generateAESKey();
  }

  Future<File> encryptFileInChunks(
      File inputFile, String fileEncryptionKey, int chunkSize,
      {String? path, String? ivBase64}) async {
    var chunkedStream = ChunkedStreamReader(inputFile.openRead());
    final length = inputFile.lengthSync();
    var readBytes = 0;
    final fileName = inputFile.uri.pathSegments.last;
    File encryptedFile;
    if (path != null) {
      encryptedFile =
          await File('$path${Platform.pathSeparator}encrypted_$fileName')
              .create();
    } else {
      encryptedFile = await File(
              '${inputFile.parent.path}${Platform.pathSeparator}encrypted_$fileName')
          .create();
    }
    try {
      while (readBytes < length) {
        final actualBytes = await chunkedStream.readBytes(chunkSize);
        final encryptedBytes = AESCodec(fileEncryptionKey, ivBase64: ivBase64)
            .encoder
            .convert(actualBytes);
        encryptedFile.writeAsBytesSync(encryptedBytes, mode: FileMode.append);
        readBytes += chunkSize;
      }
    } on Exception catch (e, trace) {
      logger.severe(e);
      logger.severe(trace);
    }
    return encryptedFile;
  }

  Future<File> decryptFileInChunks(
      File encryptedFile, String fileDecryptionKey, int chunkSize,
      {String? ivBase64}) async {
    var chunkedStream = ChunkedStreamReader(encryptedFile.openRead());
    // ignore: unused_local_variable
    var startTime = DateTime.now();
    final length = encryptedFile.lengthSync();
    final fileName = encryptedFile.uri.pathSegments.last;
    var readBytes = 0;
    final decryptedFile = File(
        '${encryptedFile.parent.path}${Platform.pathSeparator}decrypted_$fileName');
    try {
      while (readBytes < length) {
        final actualBytes = await chunkedStream.readBytes(chunkSize);
        final decryptedBytes = AESCodec(fileDecryptionKey, ivBase64: ivBase64)
            .decoder
            .convert(actualBytes);
        decryptedFile.writeAsBytesSync(decryptedBytes, mode: FileMode.append);
        readBytes += chunkSize;
      }
    } on Exception catch (e, trace) {
      logger.severe(e);
      logger.severe(trace);
    }
    return decryptedFile;
  }
}
