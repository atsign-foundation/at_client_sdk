import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Catalogue: features/at_client/stream_verb_retired.feature
void main() {
  late MockRemoteSecondary remote;
  late AtClientImpl client;
  late int connectionsBuilt;

  setUp(() async {
    remote = MockRemoteSecondary();
    connectionsBuilt = 0;
    client = await AtClientImpl.create(
        '@streamer', 'wavi', AtClientPreference(), remoteSecondary: remote,
        lookUps: ({
      required String atSign,
      required AtRootDomain rootDomain,
      required AtAuthenticator? authenticator,
      SecondaryAddressFinder? secondaryAddressFinder,
      Map<String, dynamic> clientConfig = const {},
    }) {
      connectionsBuilt++;
      throw StateError('no connection is expected');
    },
        storage: InMemoryAtClientStorage(
            atSign: '@streamer', closedByClient: true)) as AtClientImpl;
    addTearDown(client.stop);
  });

  Matcher unsupportedStreamVerb() => throwsA(isA<UnsupportedError>().having(
      (e) => e.message,
      'message',
      contains('atServers no longer support the stream verb')));

  test('AtClient.stream fails at once, sending nothing', () async {
    await expectLater(
        // ignore: deprecated_member_use_from_same_package
        () => client.stream('@bob', 'stream_verb_retired_test.dart'),
        unsupportedStreamVerb());
    verifyZeroInteractions(remote);
    expect(connectionsBuilt, 0);
  });

  test('AtClient.sendStreamAck fails at once, connecting to nothing', () async {
    await expectLater(
        // ignore: deprecated_member_use_from_same_package
        () => client.sendStreamAck(
            'stream-id', 'f.txt', 12, '@bob', (_) {}, (_) {}),
        unsupportedStreamVerb());
    verifyZeroInteractions(remote);
    expect(connectionsBuilt, 0);
  });

  group('Given an EncryptionService', () {
    final service = EncryptionService('@streamer');

    Matcher retiredWithStreamTransfer(String member) =>
        throwsA(isA<UnsupportedError>().having((e) => e.message, 'message',
            contains('$member is retired with the stream transfer')));

    test('when encryptStream is called, then it throws UnsupportedError',
        () async {
      await expectLater(
          // ignore: deprecated_member_use_from_same_package
          () => service.encryptStream([1, 2, 3], '@bob'),
          retiredWithStreamTransfer('EncryptionService.encryptStream'));
    });

    test(
        'when decryptStream is called, '
        'then it decrypts with the AES key it is given', () {
      final key = EncryptionUtil.generateAESKey();
      final iv = EncryptionUtil.generateIV();
      final encrypted =
          EncryptionUtil.encryptBytes([1, 2, 3], key, ivBase64: iv);
      expect(
          // ignore: deprecated_member_use_from_same_package
          service.decryptStream(encrypted, key, ivBase64: iv),
          [1, 2, 3]);
    });

    test(
        'when getSharedKeyForDecryption is called, '
        'then it throws UnsupportedError', () async {
      await expectLater(
          // ignore: deprecated_member_use_from_same_package
          () => service.getSharedKeyForDecryption('@bob'),
          retiredWithStreamTransfer(
              'EncryptionService.getSharedKeyForDecryption'));
    });
  });
}
