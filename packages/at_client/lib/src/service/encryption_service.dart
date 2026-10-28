import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/converters/encryption/aes_converter.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_utils/at_logger.dart';

class EncryptionService {
  RemoteSecondary? remoteSecondary;

  LocalSecondary? localSecondary;

  late final String atSign;

  late final AtSignLogger logger;

  EncryptionService(this.atSign) {
    logger = AtSignLogger('EncryptionService ($atSign)');
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
