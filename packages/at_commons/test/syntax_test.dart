import 'dart:collection';
import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests to verify notify verb regex', () {
    test('Test to verify notify verb with encryptedSharedKey and checksum', () {
      var command =
          'notify:update:priority:low:strategy:all:latestN:1:sharedKeyEnc:GxIjM8e/nsga3:pubKeyCS:5d52f6f2868:@bob:phone.wavi@alice:989745456';
      var verbParams = getVerbParams(VerbSyntax.notify, command);
      expect(verbParams[AtConstants.operation], 'update');
      expect(verbParams[AtConstants.sharedKeyEncrypted], 'GxIjM8e/nsga3');
      expect(
          verbParams[AtConstants.sharedWithPublicKeyCheckSum], '5d52f6f2868');
      expect(verbParams[AtConstants.priority], 'low');
      expect(verbParams[AtConstants.latestN], '1');
      expect(verbParams[AtConstants.value], '989745456');
      expect(verbParams[AtConstants.strategy], 'all');
    });

    test('Test to verify notify verb with delete operation', () {
      var command =
          'notify:delete:priority:low:strategy:all:latestN:1:sharedKeyEnc:GxIjM8e/nsga3:pubKeyCS:5d52f6f2868:@bob:phone.wavi@alice:989745456';
      var verbParams = getVerbParams(VerbSyntax.notify, command);
      expect(verbParams[AtConstants.operation], 'delete');
      expect(verbParams[AtConstants.sharedKeyEncrypted], 'GxIjM8e/nsga3');
      expect(
          verbParams[AtConstants.sharedWithPublicKeyCheckSum], '5d52f6f2868');
      expect(verbParams[AtConstants.priority], 'low');
      expect(verbParams[AtConstants.latestN], '1');
      expect(verbParams[AtConstants.value], '989745456');
      expect(verbParams[AtConstants.strategy], 'all');
    });
  });

  group('A group of tests to verify notify delete verb', () {
    test('Valid id sent to notify delete', () {
      var command = 'notify:remove:abcd-1234';
      var verbParams = getVerbParams(VerbSyntax.notifyRemove, command);
      expect(verbParams[AtConstants.id], 'abcd-1234');
    });

    test('id not sent to notify delete', () {
      var command = 'notify:remove:';
      expect(
          () => getVerbParams(VerbSyntax.notifyRemove, command),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message == 'command does not match the regex')));
    });
  });

  group('A group of tests to verify pkam verb regex', () {
    test('pkam regex without signing algo', () {
      var command = 'pkam:abcd1234';
      var verbParams = getVerbParams(VerbSyntax.pkam, command);
      expect(verbParams[AtConstants.atPkamSignature], 'abcd1234');
    });

    test('pkam regex with rsa2048 signing algo and sha256 hashing algo', () {
      var command = 'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:abcd1234';
      var verbParams = getVerbParams(VerbSyntax.pkam, command);
      expect(verbParams[AtConstants.atPkamSigningAlgo], 'rsa2048');
      expect(verbParams[AtConstants.atPkamHashingAlgo], 'sha256');
      expect(verbParams[AtConstants.atPkamSignature], 'abcd1234');
    });

    test('pkam regex with ecc signing algo and sha256 hashing algo', () {
      var command =
          'pkam:signingAlgo:ecc_secp256r1:hashingAlgo:sha256:abcd1234';
      var verbParams = getVerbParams(VerbSyntax.pkam, command);
      expect(verbParams[AtConstants.atPkamSigningAlgo], 'ecc_secp256r1');
      expect(verbParams[AtConstants.atPkamHashingAlgo], 'sha256');
      expect(verbParams[AtConstants.atPkamSignature], 'abcd1234');
    });

    test('pkam regex with ecc signing algo and sha512 hashing algo', () {
      var command =
          'pkam:signingAlgo:ecc_secp256r1:hashingAlgo:sha512:abcd1234';
      var verbParams = getVerbParams(VerbSyntax.pkam, command);
      expect(verbParams[AtConstants.atPkamSigningAlgo], 'ecc_secp256r1');
      expect(verbParams[AtConstants.atPkamHashingAlgo], 'sha512');
      expect(verbParams[AtConstants.atPkamSignature], 'abcd1234');
    });

    test('pkam regex with rsa signing algo and sha512 hashing algo', () {
      var command = 'pkam:signingAlgo:rsa2048:hashingAlgo:sha512:abcd1234';
      var verbParams = getVerbParams(VerbSyntax.pkam, command);
      expect(verbParams[AtConstants.atPkamSigningAlgo], 'rsa2048');
      expect(verbParams[AtConstants.atPkamHashingAlgo], 'sha512');
      expect(verbParams[AtConstants.atPkamSignature], 'abcd1234');
    });

    test('pkam regex with invalid signing algo', () {
      var command = 'pkam:signingAlgo:ecc:abcd1234';
      var verbParams = getVerbParams(VerbSyntax.pkam, command);
      expect(verbParams[AtConstants.atPkamSigningAlgo], isNull);
    });

    test('pkam regex with invalid hashing algo', () {
      var command = 'pkam:hashingAlgo:md5:abcd1234';
      var verbParams = getVerbParams(VerbSyntax.pkam, command);
      expect(verbParams[AtConstants.atPkamHashingAlgo], isNull);
    });
  });

  group('A group of positive tests to verify keys verb regex', () {
    test('keys verb  - put public key', () {
      var command =
          'keys:put:public:namespace:__global:keyType:rsa2048:keyName:encryption_123-a abcd1234';
      var verbParams = getVerbParams(VerbSyntax.keys, command);
      expect(verbParams[AtConstants.keyType], 'rsa2048');
      expect(verbParams[AtConstants.visibility], 'public');
      expect(verbParams[AtConstants.keyValue], 'abcd1234');
      expect(verbParams[AtConstants.namespace], '__global');
      expect(verbParams[AtConstants.operation], 'put');
      expect(verbParams[AtConstants.keyName], 'encryption_123-a');
    });

    test('keys verb - put private key', () {
      var command =
          'keys:put:private:namespace:__private:keyType:aes:keyName:secretKey abcd1234';
      var verbParams = getVerbParams(VerbSyntax.keys, command);
      expect(verbParams[AtConstants.keyType], 'aes');
      expect(verbParams[AtConstants.visibility], 'private');
      expect(verbParams[AtConstants.keyValue], 'abcd1234');
      expect(verbParams[AtConstants.namespace], '__private');
      expect(verbParams[AtConstants.operation], 'put');
      expect(verbParams[AtConstants.keyName], 'secretKey');
    });

    test('keys verb - put private key with app and device name', () {
      var command =
          'keys:put:private:namespace:__private:appName:wavi:deviceName:pixel:keyType:aes:keyName:secretKey abcd1234';
      var verbParams = getVerbParams(VerbSyntax.keys, command);
      expect(verbParams[AtConstants.keyType], 'aes');
      expect(verbParams[AtConstants.visibility], 'private');
      expect(verbParams[AtConstants.keyValue], 'abcd1234');
      expect(verbParams[AtConstants.namespace], '__private');
      expect(verbParams[AtConstants.operation], 'put');
      expect(verbParams[AtConstants.keyName], 'secretKey');
      expect(verbParams[AtConstants.appName], 'wavi');
      expect(verbParams[AtConstants.deviceName], 'pixel');
    });

    test('keys verb - put self key with encryption key name', () {
      var command =
          'keys:put:self:namespace:__global:keyType:aes256:encryptionKeyName:encryption_123-a:keyName:mykey zcsfsdff';
      var verbParams = getVerbParams(VerbSyntax.keys, command);
      expect(verbParams[AtConstants.keyType], 'aes256');
      expect(verbParams[AtConstants.visibility], 'self');
      expect(verbParams[AtConstants.keyValue], 'zcsfsdff');
      expect(verbParams[AtConstants.namespace], '__global');
      expect(verbParams[AtConstants.operation], 'put');
      expect(verbParams[AtConstants.keyName], 'mykey');
      expect(verbParams[AtConstants.encryptionKeyName], 'encryption_123-a');
    });

    test('keys verb - get private keys', () {
      var command = 'keys:get:private';
      var verbParams = getVerbParams(VerbSyntax.keys, command);
      expect(verbParams[AtConstants.visibility], 'private');
    });

    test('keys verb - get self keys', () {
      var command = 'keys:get:self';
      var verbParams = getVerbParams(VerbSyntax.keys, command);
      expect(verbParams[AtConstants.visibility], 'self');
    });

    test('keys verb - get public keys', () {
      var command = 'keys:get:public';
      var verbParams = getVerbParams(VerbSyntax.keys, command);
      expect(verbParams[AtConstants.visibility], 'public');
    });

    test('keys verb - get key by name', () {
      var command = 'keys:get:keyName:firstKey';
      var verbParams = getVerbParams(VerbSyntax.keys, command);
      expect(verbParams[AtConstants.operation], 'get');
      expect(verbParams[AtConstants.keyName], 'firstKey');
    });

    test('keys verb - get key by name with emoji', () {
      var command = 'keys:get:keyName:firstKey🛠';
      var verbParams = getVerbParams(VerbSyntax.keys, command);
      expect(verbParams[AtConstants.operation], 'get');
      expect(verbParams[AtConstants.keyName], 'firstKey🛠');
    });
  });

  group('A group of negative tests to keys verb regex', () {
    test('keys verb  - invalid operation', () {
      var command = 'keys:fetch:keyName:abc123';
      expect(
          () => getVerbParams(VerbSyntax.keys, command),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message == 'command does not match the regex')));
    });
  });

  group('A group of positive tests to verify monitor verb regex', () {
    test('monitor verb syntax - no additional params', () {
      var command = 'monitor';
      var verbParams = getVerbParams(VerbSyntax.monitor, command);
      expect(verbParams[AtConstants.monitorStrictMode], null);
      expect(verbParams[AtConstants.monitorMultiplexedMode], null);
      expect(verbParams[AtConstants.monitorRegex], null);
      expect(verbParams[AtConstants.epochMilliseconds], null);
    });
    test('monitor verb syntax - strict mode', () {
      var command = 'monitor:strict';
      var verbParams = getVerbParams(VerbSyntax.monitor, command);
      expect(verbParams[AtConstants.monitorStrictMode], 'strict');
    });
    test('monitor verb syntax - multiplexed mode', () {
      var command = 'monitor:multiplexed';
      var verbParams = getVerbParams(VerbSyntax.monitor, command);
      expect(verbParams[AtConstants.monitorMultiplexedMode], 'multiplexed');
    });
    test('monitor verb syntax - with last notification time', () {
      var command = 'monitor:1234';
      var verbParams = getVerbParams(VerbSyntax.monitor, command);
      expect(verbParams[AtConstants.epochMilliseconds], '1234');
    });
    test('monitor verb syntax - with regex', () {
      var command = 'monitor .wavi';
      var verbParams = getVerbParams(VerbSyntax.monitor, command);
      expect(verbParams[AtConstants.monitorRegex], '.wavi');
    });
    test('monitor verb syntax - self notification enabled', () {
      var command = 'monitor:selfNotifications';
      var verbParams = getVerbParams(VerbSyntax.monitor, command);
      print(verbParams);
      expect(verbParams[AtConstants.monitorSelfNotifications],
          'selfNotifications');
    });

    test('monitor verb syntax - multiple params', () {
      var command = 'monitor:strict:selfNotifications:multiplexed .wavi';
      var verbParams = getVerbParams(VerbSyntax.monitor, command);
      expect(verbParams[AtConstants.monitorStrictMode], 'strict');
      expect(verbParams[AtConstants.monitorMultiplexedMode], 'multiplexed');
      expect(verbParams[AtConstants.monitorSelfNotifications],
          'selfNotifications');
      expect(verbParams[AtConstants.monitorRegex], '.wavi');
    });
  });

  group('A group of tests related to enroll verb', () {
    test('A test to verify enroll request params', () {
      String command =
          'enroll:request:{"enrollmentId":"1234","appName":"wavi","deviceName":"pixel","namespaces":{"wavi":"rw","__manage":"r"},"encryptedDefaultEncryptedPrivateKey":"dummy_encrypted_private_key","encryptedDefaultSelfEncryptionKey":"dummy_self_encryption_key","encryptedAPKAMSymmetricKey":"dummy_pkam_sym_key","apkamPublicKey":"abcd1234"}\n';
      var enrollVerbParams =
          VerbUtil.getVerbParam(VerbSyntax.enroll, command.trim())!;
      expect(enrollVerbParams['operation'], 'request');
      var verbParams = jsonDecode(enrollVerbParams['enrollParams']!);
      expect(verbParams['enrollmentId'], '1234');
      expect(verbParams['appName'], 'wavi');
      expect(verbParams['deviceName'], 'pixel');
      expect(verbParams['namespaces']['wavi'], 'rw');
      expect(verbParams['namespaces']['__manage'], 'r');
      expect(verbParams['encryptedDefaultEncryptedPrivateKey'],
          'dummy_encrypted_private_key');
      expect(verbParams['encryptedDefaultSelfEncryptionKey'],
          'dummy_self_encryption_key');
      expect(verbParams['encryptedAPKAMSymmetricKey'], 'dummy_pkam_sym_key');
      expect(verbParams['apkamPublicKey'], 'abcd1234');
    });

    test('A test to verify enroll approve params', () {
      String command =
          'enroll:approve:{"enrollmentId":"1234","appName":"wavi","deviceName":"pixel","namespaces":{"wavi":"rw","__manage":"r"},"encryptedDefaultEncryptedPrivateKey":"dummy_encrypted_private_key","encryptedDefaultSelfEncryptionKey":"dummy_self_encryption_key","encryptedAPKAMSymmetricKey":"dummy_pkam_sym_key","apkamPublicKey":"abcd1234"}\n';
      var enrollVerbParams =
          VerbUtil.getVerbParam(VerbSyntax.enroll, command.trim())!;
      expect(enrollVerbParams['operation'], 'approve');
      var verbParams = jsonDecode(enrollVerbParams['enrollParams']!);
      expect(verbParams['enrollmentId'], '1234');
      expect(verbParams['appName'], 'wavi');
      expect(verbParams['deviceName'], 'pixel');
      expect(verbParams['namespaces']['wavi'], 'rw');
      expect(verbParams['namespaces']['__manage'], 'r');
      expect(verbParams['encryptedDefaultEncryptedPrivateKey'],
          'dummy_encrypted_private_key');
      expect(verbParams['encryptedDefaultSelfEncryptionKey'],
          'dummy_self_encryption_key');
      expect(verbParams['encryptedAPKAMSymmetricKey'], 'dummy_pkam_sym_key');
      expect(verbParams['apkamPublicKey'], 'abcd1234');
    });

    test('A test to verify enroll deny params', () {
      String command = 'enroll:deny:{"enrollmentId":"1234"}\n';
      var enrollVerbParams =
          VerbUtil.getVerbParam(VerbSyntax.enroll, command.trim())!;
      expect(enrollVerbParams['operation'], 'deny');
      var verbParams = jsonDecode(enrollVerbParams['enrollParams']!);
      expect(verbParams['enrollmentId'], '1234');
    });

    test('A test to verify enroll revoke params', () {
      String command = 'enroll:revoke:{"enrollmentId":"1234"}\n';
      var enrollVerbParams =
          VerbUtil.getVerbParam(VerbSyntax.enroll, command.trim())!;
      expect(enrollVerbParams['operation'], 'revoke');
      var verbParams = jsonDecode(enrollVerbParams['enrollParams']!);
      expect(verbParams['enrollmentId'], '1234');
    });

    test('A test to verify enroll revoke with force flag', () {
      String command = 'enroll:revoke:force:{"enrollmentId":"1234"}\n';
      var enrollVerbParams =
          VerbUtil.getVerbParam(VerbSyntax.enroll, command.trim())!;
      expect(enrollVerbParams['operation'], 'revoke');
      expect(enrollVerbParams['force'], 'force');
      var verbParams = jsonDecode(enrollVerbParams['enrollParams']!);
      expect(verbParams['enrollmentId'], '1234');
    });

    test('A test to assert enroll list command', () {
      String command = 'enroll:list\n';
      var enrollVerbParams =
          VerbUtil.getVerbParam(VerbSyntax.enroll, command.trim())!;
      expect(enrollVerbParams['operation'], 'list');
    });

    test('A test to verify enroll list throws exception if appended with :',
        () {
      String command = 'enroll:list:\n';
      expect(
          () => getVerbParams(VerbSyntax.enroll, command),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message == 'command does not match the regex')));
    });

    test('A test to validate enroll delete command', () {
      String command = 'enroll:delete:{"enrollmentId":"4567"}\n';
      var enrollVerbParams =
          VerbUtil.getVerbParam(VerbSyntax.enroll, command.trim());
      expect(enrollVerbParams!['operation'], 'delete');
      var enrollmentInfo = jsonDecode(enrollVerbParams['enrollParams']!);
      expect(enrollmentInfo['enrollmentId'], '4567');
    });
  });

  group('A group of tests related to otp verb', () {
    test('A test to verify otp verb for get operation', () {
      String command = 'otp:get\n';
      var enrollVerbParams =
          VerbUtil.getVerbParam(VerbSyntax.otp, command.trim())!;
      expect(enrollVerbParams['operation'], 'get');
    });
  });
}

Map getVerbParams(String regex, String command) {
  var regExp = RegExp(regex, caseSensitive: false);
  if (!regExp.hasMatch(command)) {
    throw InvalidSyntaxException('command does not match the regex');
  }
  var regexMatches = regExp.allMatches(command);
  var paramsMap = HashMap<String, String?>();
  for (var f in regexMatches) {
    for (var name in f.groupNames) {
      paramsMap.putIfAbsent(name, () => f.namedGroup(name));
    }
  }
  return paramsMap;
}
