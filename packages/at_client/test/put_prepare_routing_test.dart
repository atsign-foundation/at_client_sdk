import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Records the route a put hands the provider's prepare step, which is the
/// route any record the provider writes there (a content key's conveyance)
/// takes.
class _PreparingProvider extends CryptoProvider implements PreparesWrites {
  @override
  String get id => 'preparing-provider';

  final List<bool?> routes = [];

  @override
  Future<void> prepareForWrite(CryptoContext context, AtKey atKey,
      {bool? useRemoteAtServer}) async {
    routes.add(useRemoteAtServer);
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

void main() {
  setUpAll(() => registerFallbackValue(UpdateVerbBuilder()));

  late _PreparingProvider provider;
  late MockRemoteSecondary remote;

  setUp(() {
    provider = _PreparingProvider();
    remote = MockRemoteSecondary();
    when(() => remote.executeVerb(any())).thenAnswer((_) async => 'data:1');
  });

  Future<AtClientImpl> client(RemoteLocalPref remoteLocalPref) async =>
      await AtClientImpl.create(
          '@alice',
          'wavi',
          AtClientPreference()
            // ignore: deprecated_member_use_from_same_package
            ..isLocalStoreRequired = false
            ..remoteLocalPref = remoteLocalPref
            ..crypto = CryptoConfig(
                defaultProviderId: provider.id, providers: [provider]),
          remoteSecondary: remote) as AtClientImpl;

  AtKey selfKey() =>
      AtKey.self('phone', namespace: 'wavi', sharedBy: '@alice').build();

  test(
      'a put routed to the atServer by the preference prepares for the '
      'atServer', () async {
    final atClient = await client(RemoteLocalPref.remoteOnly);

    await atClient.put(selfKey(), 'value');

    verify(() => remote.executeVerb(any())).called(1);
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
}
