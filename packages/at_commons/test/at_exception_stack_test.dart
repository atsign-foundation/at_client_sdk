import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for exception stack', () {
    test('chained exception list size greater than zero - check trace message',
        () {
      final atChainedException = AtChainedException(
          Intent.syncData, ExceptionScenario.invalidKeyFormed, 'sync issue');
      final exceptionStack = AtExceptionStack();
      exceptionStack.add(atChainedException);
      expect(exceptionStack.getTraceMessage(), isNotEmpty);
      expect(exceptionStack.getTraceMessage(),
          startsWith('Failed to syncData caused by'));
    });

    test('check intent message', () {
      final atChainedException = AtChainedException(
          Intent.syncData, ExceptionScenario.invalidKeyFormed, 'sync issue');
      final exceptionStack = AtExceptionStack();
      exceptionStack.add(atChainedException);
      expect(exceptionStack.getIntentMessage(Intent.syncData), isNotEmpty);
      expect(exceptionStack.getIntentMessage(Intent.syncData),
          equals('Failed to syncData'));
    });

    test('chained exception list size is zero', () {
      final exceptionStack = AtExceptionStack();
      expect(exceptionStack.getTraceMessage(), isEmpty);
    });

    test('no namespace provided - check trace message', () {
      final atChainedException = AtChainedException(Intent.validateKey,
          ExceptionScenario.noNamespaceProvided, 'name space is not provided');
      final exceptionStack = AtExceptionStack();
      exceptionStack.add(atChainedException);
      expect(exceptionStack.getTraceMessage(), isNotEmpty);
      expect(exceptionStack.getTraceMessage(),
          startsWith('Failed to validateKey caused by'));
    });

    test('atsign does not exist - check trace message', () {
      final atChainedException = AtChainedException(Intent.shareData,
          ExceptionScenario.atSignDoesNotExist, 'atsign does not exist');
      final exceptionStack = AtExceptionStack();
      exceptionStack.add(atChainedException);
      expect(exceptionStack.getTraceMessage(), isNotEmpty);
      expect(exceptionStack.getTraceMessage(),
          startsWith('Failed to shareData caused by'));
    });

    test('Decryption failed - check trace message', () {
      final atChainedException = AtChainedException(Intent.decryptData,
          ExceptionScenario.decryptionFailed, 'Decryption failed');
      final exceptionStack = AtExceptionStack();
      exceptionStack.add(atChainedException);
      expect(exceptionStack.getTraceMessage(), isNotEmpty);
      expect(exceptionStack.getTraceMessage(),
          startsWith('Failed to decryptData caused by'));
    });

    test('Encryption private key not found - check trace message', () {
      final atChainedException = AtChainedException(
          Intent.fetchEncryptionPrivateKey,
          ExceptionScenario.fetchEncryptionKeys,
          'Encryption keys not found');
      final exceptionStack = AtExceptionStack();
      exceptionStack.add(atChainedException);
      expect(exceptionStack.getTraceMessage(), isNotEmpty);
      expect(exceptionStack.getTraceMessage(),
          startsWith('Failed to fetchEncryptionPrivateKey caused by'));
    });

    test('Notification failed - check trace message', () {
      final atChainedException = AtChainedException(
          Intent.notifyData,
          ExceptionScenario.secondaryServerNotReachable,
          'Secondary server not reachable');
      final exceptionStack = AtExceptionStack();
      exceptionStack.add(atChainedException);
      expect(exceptionStack.getTraceMessage(), isNotEmpty);
      expect(exceptionStack.getTraceMessage(),
          startsWith('Failed to notifyData caused by'));
    });
  });
}
