import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:at_client/src/client/at_client_impl.dart';
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

  String? currentAtSign;

  var logger = AtSignLogger('EncryptionService');

  @experimental
  AtTelemetryService? telemetry;

  Future<List<int>> encryptStream(List<int> value, String sharedWith) async {
    return EncryptionUtil.encryptBytes(
        value, await _getAESKeyForEncryption(sharedWith));
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

  List<int> decryptStream(List<int> encryptedValue, String sharedKey) {
    //decrypt stream using decrypted aes shared key
    var decryptedValue = EncryptionUtil.decryptBytes(encryptedValue, sharedKey);
    return decryptedValue;
  }

  @Deprecated('Not in use')
  Future<void> encryptUnencryptedData() async {
    var atClient = await (AtClientImpl.getClient(currentAtSign));
    if (atClient == null) {
      return;
    }
    var selfKeys = await atClient.getAtKeys(sharedBy: currentAtSign);
    // ignore: avoid_function_literals_in_foreach_calls
    selfKeys.forEach((atKey) async {
      var key = atKey.key!;
      if (!(key.startsWith(AT_PKAM_PRIVATE_KEY) ||
          key.startsWith(AT_PKAM_PUBLIC_KEY) ||
          key.startsWith(AT_ENCRYPTION_PRIVATE_KEY) ||
          key.startsWith(AT_SIGNING_PRIVATE_KEY) ||
          key.startsWith(AT_ENCRYPTION_SHARED_KEY) ||
          key.startsWith('_'))) {
        var sharedWith = atKey.sharedWith;
        var isPublic = false;
        var isCached = false;
        if (atKey.metadata != null) {
          isPublic = atKey.metadata?.isPublic ?? false;
          isCached = atKey.metadata?.isCached ?? false;
        }
        if (!isPublic && !isCached) {
          if (sharedWith == null || sharedWith == currentAtSign) {
            var atValue = await atClient.get(atKey);
            var metadata =
                (atValue.metadata != null) ? atValue.metadata! : Metadata();
            var isEncrypted =
                (metadata.isEncrypted != null) ? metadata.isEncrypted! : false;
            if (!isEncrypted) {
              var value = atValue.value;
              metadata.isEncrypted = true;
              metadata.isBinary =
                  (metadata.isBinary != null) ? metadata.isBinary : false;
              atKey.metadata = metadata;
              await atClient.put(atKey, value);
            }
          }
        }
      }
    });
    await atClient.getSyncManager()!.sync();
  }

  /// Returns sharedWith atSign publicKey.
  /// Throws [KeyNotFoundException] if sharedWith atSign publicKey is not found.
  Future<String?> _getSharedWithPublicKey(String sharedWithUser) async {
    //a local lookup the cached public key of sharedWith atsign.
    String? sharedWithPublicKey;
    var cachedPublicKeyBuilder = LLookupVerbBuilder()
      ..atKey = 'publickey.$sharedWithUser'
      ..sharedBy = currentAtSign;
    try {
      sharedWithPublicKey =
          await localSecondary!.executeVerb(cachedPublicKeyBuilder);
    } on KeyNotFoundException {
      logger.finer(
          '${cachedPublicKeyBuilder.atKey}@$currentAtSign not found in local secondary. Fetching from cloud secondary');
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
      ..sharedBy = currentAtSign
      ..value = sharedWithPublicKey;
    await localSecondary!.executeVerb(sharedWithPublicKeyBuilder, sync: true);
    return sharedWithPublicKey;
  }

  Future<String?> _getSharedKeyFromLocalForEncryption(String sharedWith) async {
    final sharedWithUser = sharedWith.replaceFirst('@', '');
    final llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = '$AT_ENCRYPTION_SHARED_KEY.$sharedWithUser'
      ..sharedBy = currentAtSign;
    String? sharedKey;
    try {
      sharedKey = await localSecondary!.executeVerb(llookupVerbBuilder);
    } on KeyNotFoundException {
      logger.finer(
          '${llookupVerbBuilder.atKey}$currentAtSign not found in local secondary. Fetching from cloud secondary.');
    }
    return sharedKey;
  }

  Future<String?> _getSharedKeyFromRemoteForEncryption(
      String sharedWith) async {
    final sharedWithUser = sharedWith.replaceFirst('@', '');
    final llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = '$AT_ENCRYPTION_SHARED_KEY.$sharedWithUser'
      ..sharedBy = currentAtSign;
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
      ..sharedBy = currentAtSign
      ..atKey = AT_ENCRYPTION_SHARED_KEY;
    String? result;
    try {
      result = await localSecondary!.executeVerb(lookupEncryptionSharedKey);
    } on KeyNotFoundException {
      logger.finer(
          '$sharedWith:$AT_ENCRYPTION_SHARED_KEY@$currentAtSign not found in local secondary. Fetching from cloud secondary');
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
        ..sharedBy = currentAtSign
        ..atKey = AT_ENCRYPTION_SHARED_KEY
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
        await localSecondary!.getEncryptionPublicKey(currentAtSign!);
    var encryptedSharedKeyForCurrentAtSign =
        EncryptionUtil.encryptKey(sharedKey, currentAtSignPublicKey!);

    var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
      ..sharedBy = currentAtSign
      ..atKey = '$AT_ENCRYPTION_SHARED_KEY.$sharedWithUser'
      ..value = encryptedSharedKeyForCurrentAtSign;
    await localSecondary!
        .executeVerb(updateSharedKeyForCurrentAtSignBuilder, sync: true);
  }

  Future<String?> _getSharedKeyForDecryption(String sharedBy) async {
    String? encryptedSharedKey;
    var localLookupSharedKeyBuilder = LLookupVerbBuilder()
      ..isCached = true
      ..sharedBy = sharedBy
      ..sharedWith = currentAtSign
      ..atKey = AT_ENCRYPTION_SHARED_KEY;
    try {
      encryptedSharedKey =
          await localSecondary!.executeVerb(localLookupSharedKeyBuilder);
    } on KeyNotFoundException {
      logger.finer(
          '$sharedBy:${localLookupSharedKeyBuilder.atKey}@$currentAtSign not found in local secondary. Fetching from cloud secondary');
    }
    if (encryptedSharedKey == null || encryptedSharedKey == 'data:null') {
      var sharedKeyLookUpBuilder = LookupVerbBuilder()
        ..atKey = AT_ENCRYPTION_SHARED_KEY
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
        EncryptionUtil.decryptKey(encryptedSharedKey, currentAtSignPrivateKey);
    return sharedKey;
  }

  /// Used in atmosphere pro
  String generateFileEncryptionKey() {
    return EncryptionUtil.generateAESKey();
  }

  Future<File> encryptFileInChunks(
      File inputFile, String fileEncryptionKey, int chunkSize,
      {String? path}) async {
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
        final encryptedBytes =
            AESCodec(fileEncryptionKey).encoder.convert(actualBytes);
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
      File encryptedFile, String fileDecryptionKey, int chunkSize) async {
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
        final decryptedBytes =
            AESCodec(fileDecryptionKey).decoder.convert(actualBytes);
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
