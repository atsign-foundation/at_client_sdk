import 'package:at_client/at_client_io.dart';
import 'package:at_client/memory.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

/// Records the route a put hands the provider's prepare step, which is the
/// route any record the provider writes there (a content key's conveyance)
/// takes, and the namespace it is required to seal to.
class _PreparingProvider extends CryptoProvider implements PreparesWrites {
  _PreparingProvider([this.id = 'preparing-provider']);

  @override
  final String id;

  final List<bool?> routes = [];

  final List<String?> sealedTo = [];

  @override
  Future<void> prepareForWrite(CryptoContext context, AtKey atKey,
      {bool? useRemoteAtServer, String? sealToNamespace}) async {
    routes.add(useRemoteAtServer);
    sealedTo.add(sealToNamespace);
  }

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String value) async {
    atKey.metadata.appMetadata = AppMetadata(providerId: id);
    atKey.metadata.isEncrypted = true;
    return value;
  }

  @override
  Future<String> decrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      value;
}

/// Stands in for the legacy provider, so a put routed to it is told by the
/// provider id it is written under.
class _Legacy extends CryptoProvider {
  @override
  String get id => legacyCryptoProviderId;

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String value) async {
    atKey.metadata.appMetadata = AppMetadata(providerId: id);
    atKey.metadata.isEncrypted = true;
    return value;
  }

  @override
  Future<String> decrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      value;
}

void main() {
  setUpAll(() => registerFallbackValue(UpdateVerbBuilder()));

  late _PreparingProvider provider;
  late MockRemoteSecondary remote;

  setUp(() {
    provider = _PreparingProvider();
    remote = MockRemoteSecondary();
    when(() => remote.executeVerb(any())).thenAnswer((_) async => 'data:1');
  });

  Future<AtClientImpl> client(RemoteLocalPref remoteLocalPref,
      {PqPosture posture = PqPosture.legacy, String? defaultProviderId}) async {
    final built = await AtClientImpl.create(
            '@alice',
            'wavi',
            AtClientPreference(posture: posture)
              ..remoteLocalPref = remoteLocalPref
              ..crypto = CryptoConfig(
                  defaultProviderId: defaultProviderId ?? provider.id,
                  providers: [provider, _Legacy()]),
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: defaultAtDirectory,
            atKeysIo: noKeysFor('@alice'),
            remoteSecondary: remote,
            storage:
                InMemoryAtClientStorage(atSign: '@alice', closedByClient: true))
        as AtClientImpl;
    addTearDown(built.stop);
    return built;
  }

  AtKey selfKey() =>
      AtKey.self('phone', namespace: 'wavi', sharedBy: '@alice').build();

  test(
      'a put routed to the atServer by the preference prepares for the '
      'atServer', () async {
    final atClient = await client(RemoteLocalPref.remoteOnly);

    await atClient.put(selfKey(), 'value');

    verify(() => remote.executeVerb(any(that: isA<UpdateVerbBuilder>())))
        .called(1);
    expect(provider.routes, [true],
        reason: 'the value went to the atServer, so a conveyance written in '
            'the prepare step must go there too, or the value cites a key '
            'that only exists locally');
  });

  test('control: a put routed to the atServer by its own options', () async {
    final atClient = await client(RemoteLocalPref.remoteOnly);

    await atClient.put(selfKey(), 'value',
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);

    expect(provider.routes, [true]);
  });

  test(
      'a put requiring a namespace and naming no provider is written under the '
      'namespace-key provider', () async {
    provider = _PreparingProvider(symmetricAesGcmCryptoProviderId);
    final atClient = await client(RemoteLocalPref.remoteOnly,
        posture: PqPosture.pqReady, defaultProviderId: legacyCryptoProviderId);

    await atClient.put(
        AtKey.fromString('@bob:reading.d1.sensor@alice'), 'value',
        putRequestOptions: PutRequestOptions()
          ..useRemoteAtServer = true
          ..sealToNamespace = 'd1.sensor');

    expect(provider.sealedTo, ['d1.sensor']);
    final sent = verify(() =>
            remote.executeVerb(captureAny(that: isA<UpdateVerbBuilder>())))
        .captured
        .single as UpdateVerbBuilder;
    expect(sent.atKey.metadata.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId);
  });
}
