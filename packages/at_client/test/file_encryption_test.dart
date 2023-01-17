import 'dart:io';

import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:test/test.dart';

void main() {
  group('A group of file encryption tests', () {
    test('encrypt file - file size less than chunk size', () async {
      final originalFile = File('test/data/encryption/hello.txt');
      final encryptionService = EncryptionService("@testAtSign");
      final fileEncryptionKey = EncryptionUtil.generateAESKey();
      final encryptedFile = await encryptionService.encryptFileInChunks(
          originalFile, fileEncryptionKey, 4096);
      expect(encryptedFile.lengthSync(), originalFile.lengthSync());
      encryptedFile.deleteSync();
    });

    test('encrypt file - file size greater than chunk size', () async {
      final originalFile = File('test/data/encryption/dog.jpeg');
      final encryptionService = EncryptionService("@testAtSign");
      final fileEncryptionKey = EncryptionUtil.generateAESKey();
      final encryptedFile = await encryptionService.encryptFileInChunks(
          originalFile, fileEncryptionKey, 4096);
      expect(encryptedFile.lengthSync(), originalFile.lengthSync());
      encryptedFile.deleteSync();
    });

    test('decrypt file - text file', () async {
      final originalFile = File('test/data/encryption/hello.txt');
      final encryptionService = EncryptionService("@testAtSign");
      final fileEncryptionKey = EncryptionUtil.generateAESKey();
      final encryptedFile = await encryptionService.encryptFileInChunks(
          originalFile, fileEncryptionKey, 4096);
      final decryptedFile = await encryptionService.decryptFileInChunks(
          encryptedFile, fileEncryptionKey, 4096);
      expect(decryptedFile.readAsStringSync(), originalFile.readAsStringSync());
      encryptedFile.deleteSync();
      decryptedFile.deleteSync();
    });

    test('decrypt file - image ', () async {
      final originalFile = File('test/data/encryption/cat.jpeg');
      final encryptionService = EncryptionService("@testAtSign");
      final fileEncryptionKey = EncryptionUtil.generateAESKey();
      final encryptedFile = await encryptionService.encryptFileInChunks(
          originalFile, fileEncryptionKey, 4096);
      final decryptedFile = await encryptionService.decryptFileInChunks(
          encryptedFile, fileEncryptionKey, 4096);
      expect(decryptedFile.lengthSync(), originalFile.lengthSync());
      encryptedFile.deleteSync();
      decryptedFile.deleteSync();
    });
  });
}
