import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show AtData, AtKeyValueStore, AtMetaData;
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

class _MockKeyStore extends Mock
    implements AtKeyValueStore<String, AtData, AtMetaData?> {}

/// A client of [AtClientBindings], to drive its `notify`.
class _Bound with AtClientBindings {
  @override
  final AtClient atClient;
  @override
  final AtSignLogger logger = AtSignLogger('received_scheme_test');
  _Bound(this.atClient);
}

/// Telling how a shared value was protected, and answering in kind.
void main() {
  const me = '@bob';
  const sender = '@alice';

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(NotificationParams.forText('', me));
    registerFallbackValue(LookupVerbBuilder());
  });

  AtKey sharedValue({AppMetadata? appMetadata}) => AtKey()
    ..key = 'order42'
    ..namespace = 'orders.my_app'
    ..sharedBy = sender
    ..sharedWith = me
    ..metadata = (Metadata()..appMetadata = appMetadata);

  /// A client whose local store holds [stored] and whose atServer serves
  /// [served], each by at-key string. The atServer answers `lookup:meta` and
  /// nothing else, and the client reads no value.
  MockAtClient clientWith(Map<String, Metadata> stored,
      {Map<String, Metadata> served = const {}, List<String>? sent}) {
    final client = MockAtClient();
    final local = MockLocalSecondary();
    final keyStore = _MockKeyStore();
    final remote = MockRemoteSecondary();
    when(() => client.getCurrentAtSign()).thenReturn(me);
    when(() => client.getLocalSecondary()).thenReturn(local);
    when(() => local.keyStore).thenReturn(keyStore);
    when(() => keyStore.getMeta(any())).thenAnswer((inv) async {
      final metadata = stored[inv.positionalArguments[0]];
      return metadata == null
          ? null
          : AtMetaData.fromCommonsMetadata(metadata, me);
    });
    when(() => client.getRemoteSecondary()).thenReturn(remote);
    when(() => remote.executeVerb(any())).thenAnswer((inv) async {
      final command =
          (inv.positionalArguments[0] as VerbBuilder).buildCommand();
      sent?.add(command.trim());
      final meta = RegExp(r'^lookup:meta:(.+)\n$').firstMatch(command);
      if (meta == null) throw StateError('unexpected command: $command');
      final metadata = served[meta.group(1)];
      if (metadata == null) throw AtKeyNotFoundException(meta.group(1)!);
      return 'data:${jsonEncode(metadata.toJson())}';
    });
    when(() => client.getMeta(any())).thenAnswer((inv) async =>
        throw StateError(
            'getMeta reads the value: ${inv.positionalArguments[0]}'));
    return client;
  }

  group('ReceivedScheme', () {
    test('a post-quantum provider is post-quantum and legacy is not', () {
      expect(
          const ReceivedScheme(providerId: symmetricAesGcmCryptoProviderId)
              .isPostQuantum,
          isTrue);
      expect(
          const ReceivedScheme(providerId: legacyCryptoProviderId)
              .isPostQuantum,
          isFalse);
    });

    test('two schemes with the same parts are equal, so they group', () {
      expect(
          const ReceivedScheme(
              providerId: symmetricAesGcmCryptoProviderId,
              keyAlgorithm: 'x-wing',
              suite: 'x-wing-rfc9180-v1'),
          const ReceivedScheme(
              providerId: symmetricAesGcmCryptoProviderId,
              keyAlgorithm: 'x-wing',
              suite: 'x-wing-rfc9180-v1'));
      expect(
          [legacyCryptoProviderId, legacyCryptoProviderId]
              .map((id) => ReceivedScheme(providerId: id))
              .toSet(),
          hasLength(1));
    });
  });

  group('AtNotification.receivedUnder', () {
    test('is the provider the sender stamped', () {
      final n = AtNotification.empty()
        ..metadata = (Metadata()
          ..appMetadata =
              AppMetadata(providerId: symmetricAesGcmCryptoProviderId));
      expect(n.receivedUnder, symmetricAesGcmCryptoProviderId);
    });

    test('is legacy when the sender stamped none', () {
      expect((AtNotification.empty()..metadata = Metadata()).receivedUnder,
          legacyCryptoProviderId,
          reason: 'an older client stamps nothing, and its value is read as '
              'legacy, so legacy is the scheme to answer it in');
      expect(AtNotification.empty().receivedUnder, legacyCryptoProviderId);
    });
  });

  group('AtClient.schemeOf', () {
    test('a value stamped legacy is legacy, with no algorithm or suite',
        () async {
      final scheme = await clientWith({}).schemeOf(sharedValue(
          appMetadata: AppMetadata(providerId: legacyCryptoProviderId)));
      expect(scheme, const ReceivedScheme(providerId: legacyCryptoProviderId));
    });

    test('a value sealed straight to an nskey names its KEM in its provider',
        () async {
      final scheme = await clientWith({}).schemeOf(sharedValue(
          appMetadata: AppMetadata(providerId: nskeyCryptoProviderId)));
      expect(scheme.keyAlgorithm, SecretSharingAlgos.xWing);
      expect(scheme.suite, SecretSharingAlgos.xWingRfc9180);
    });

    test('an AES-GCM value takes its KEM from the conveyance of its key',
        () async {
      final value = sharedValue(
          appMetadata: AppMetadata(
              providerId: symmetricAesGcmCryptoProviderId,
              additional: {'ckKid': 'ck1', 'ns': 'orders.my_app'}));
      final conveyance = SymmetricAesGcmProvider.openableConveyanceKeyFor(
          value, 'ck1', 'orders.my_app', me);
      final cached = AtKey()
        ..key = conveyance.key
        ..namespace = conveyance.namespace
        ..sharedBy = conveyance.sharedBy
        ..sharedWith = conveyance.sharedWith
        ..metadata = (Metadata()..isCached = true);

      final scheme = await clientWith({
        cached.toString(): Metadata()
          ..appMetadata = AppMetadata(providerId: mlKemNskeyCryptoProviderId),
      }).schemeOf(value);

      expect(scheme.providerId, symmetricAesGcmCryptoProviderId);
      expect(scheme.keyAlgorithm, SecretSharingAlgos.mlKem1024,
          reason: 'the value itself names only AES-GCM; which KEM sealed its '
              'content key is on the record that conveyed it');
      expect(scheme.suite, SecretSharingAlgos.mlKem1024Rfc9180);
    });

    test('a conveyance that cannot be read leaves the KEM unknown', () async {
      final scheme = await clientWith({}).schemeOf(sharedValue(
          appMetadata: AppMetadata(
              providerId: symmetricAesGcmCryptoProviderId,
              additional: {'ckKid': 'ck1', 'ns': 'orders.my_app'})));
      expect(scheme.isPostQuantum, isTrue);
      expect(scheme.keyAlgorithm, isNull,
          reason: 'unknown, rather than a guess at the algorithm');
      expect(scheme.suite, isNull);
    });

    test('a key with no metadata of its own is read from local storage',
        () async {
      final bare = sharedValue()..metadata = Metadata();
      final scheme = await clientWith({
        bare.toString(): Metadata()
          ..appMetadata = AppMetadata(providerId: mlKemNskeyCryptoProviderId),
      }).schemeOf(bare);
      expect(scheme.providerId, mlKemNskeyCryptoProviderId,
          reason: 'getAtKeys returns bare keys, and a scan over them is what '
              'this is for');
    });

    test('a value only the atServer holds is told from its metadata alone',
        () async {
      final value = sharedValue()..metadata = Metadata();
      final conveyance = SymmetricAesGcmProvider.openableConveyanceKeyFor(
          value, 'ck1', 'orders.my_app', me);
      final sent = <String>[];

      final scheme = await clientWith({},
          sent: sent,
          served: {
            'order42.orders.my_app$sender': Metadata()
              ..appMetadata = AppMetadata(
                  providerId: symmetricAesGcmCryptoProviderId,
                  additional: {'ckKid': 'ck1', 'ns': 'orders.my_app'}),
            '${conveyance.key}.${conveyance.namespace}$sender': Metadata()
              ..appMetadata = AppMetadata(providerId: nskeyCryptoProviderId),
          }).schemeOf(value);

      expect(scheme.keyAlgorithm, SecretSharingAlgos.xWing);
      expect(sent, everyElement(startsWith('lookup:meta:')),
          reason: 'neither the value nor its content key is read, so a scan '
              'decrypts nothing and costs one lookup per record');
      expect(sent, hasLength(2));
    });
  });

  group('AtClientBindings.notify', () {
    test('sends under the provider it is given, and the default otherwise',
        () async {
      final client = MockAtClient();
      final notifications = MockNotificationService();
      when(() => client.notificationService).thenReturn(notifications);
      when(() => client.isStopped).thenReturn(false);
      final sent = <NotificationParams>[];
      when(() => notifications.notify(any(),
          checkForFinalDeliveryStatus:
              any(named: 'checkForFinalDeliveryStatus'),
          waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
          onSuccess: any(named: 'onSuccess'),
          onError: any(named: 'onError'))).thenAnswer((inv) async {
        sent.add(inv.positionalArguments[0] as NotificationParams);
        return NotificationResult();
      });
      final bound = _Bound(client);

      await bound.notify(sharedValue(), 'answer',
          checkForFinalDeliveryStatus: false,
          waitForFinalDeliveryStatus: false,
          ttln: const Duration(minutes: 1),
          cryptoProviderId: legacyCryptoProviderId);
      await bound.notify(sharedValue(), 'answer',
          checkForFinalDeliveryStatus: false,
          waitForFinalDeliveryStatus: false,
          ttln: const Duration(minutes: 1));

      expect(
          sent.map((p) => p.cryptoProviderId), [legacyCryptoProviderId, null]);
    });
  });
}
