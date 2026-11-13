/// Catalogue: features/at_client/request_options_unset_routing.feature
library;

import 'package:at_client/at_client_io.dart';
import 'package:at_client/memory.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/no_keys.dart';
import 'test_utils/recording_remote.dart';
import 'test_utils/transport.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

void main() {
  AtSignLogger.root_level = 'shout';

  late List<String> events;
  late Map<String, String> remoteData;
  late Map<String, Metadata> remoteMeta;

  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  setUp(() {
    events = [];
    remoteData = {};
    remoteMeta = {};
  });

  /// A client of [atSign] over the recording remote, with [events] emptied
  /// once it is built. Each test names its own atSign: `AtClientImpl.create`
  /// hands back a cached client for an atSign it has seen.
  Future<AtClientImpl> clientFor(String atSign,
      {RemoteLocalPref? remoteLocalPref}) async {
    final preference = AtClientPreference();
    if (remoteLocalPref != null) preference.remoteLocalPref = remoteLocalPref;
    final client = await AtClientImpl.create(atSign, 'testing', preference,
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: await refusingAtDirectory(),
            atKeysIo: noKeysFor(atSign),
            remoteSecondary: buildRecordingRemote(
                events: events, remoteData: remoteData, remoteMeta: remoteMeta),
            storage:
                InMemoryAtClientStorage(atSign: atSign, closedByClient: true))
        as AtClientImpl;
    addTearDown(client.stop);
    events.clear();
    return client;
  }

  AtKey selfKey(String atSign) => AtKey()
    ..key = 'routed'
    ..namespace = 'testing'
    ..sharedBy = atSign
    ..metadata = (Metadata()..namespaceAware = true);

  Future<String?> storedLocally(AtClientImpl client, AtKey key) async =>
      (await client.getLocalSecondary()!.keyStore!.get(key.toString()))?.data;

  const writeOutline = 'Under remoteOnly, a write whose options leave '
      'useRemoteAtServer unset reaches the atServer before it returns';

  test('$writeOutline: put, PutRequestOptions, shouldEncrypt, update',
      () async {
    const atSign = '@unsetput';
    final client =
        await clientFor(atSign, remoteLocalPref: RemoteLocalPref.remoteOnly);
    final key = selfKey(atSign);

    final sentByReturn = await client
        .put(key, 'a value',
            putRequestOptions: PutRequestOptions()..shouldEncrypt = false)
        .then((_) => List.of(events));

    expect(sentByReturn, contains('update:$key'));
  });

  test('$writeOutline: delete, DeleteRequestOptions, noCommit, delete',
      () async {
    const atSign = '@unsetdelete';
    final client =
        await clientFor(atSign, remoteLocalPref: RemoteLocalPref.remoteOnly);
    final key = selfKey(atSign);

    final sentByReturn = await client
        .delete(key,
            deleteRequestOptions: DeleteRequestOptions()..noCommit = true)
        .then((_) => List.of(events));

    expect(sentByReturn, contains('delete:$key'));
  });

  test(
      'Under remoteOnly, a get whose options leave useRemoteAtServer unset '
      'reads from the atServer', () async {
    const atSign = '@unsetget';
    final client =
        await clientFor(atSign, remoteLocalPref: RemoteLocalPref.remoteOnly);
    final key = selfKey(atSign);
    final name = 'routed.testing$atSign';
    remoteData[name] = 'a value';
    remoteMeta[name] = Metadata()..isEncrypted = false;

    final value = await client.get(key, getRequestOptions: GetRequestOptions());

    expect(events, contains('get:$name'));
    expect(value.value, 'a value',
        reason: 'only the atServer holds the record');
  });

  test(
      'An explicit useRemoteAtServer false still routes local under remoteOnly',
      () async {
    const atSign = '@explicitlocal';
    final client =
        await clientFor(atSign, remoteLocalPref: RemoteLocalPref.remoteOnly);
    final key = selfKey(atSign);

    final sentByReturn = await client
        .put(key, 'a value',
            putRequestOptions: PutRequestOptions()
              ..useRemoteAtServer = false
              ..shouldEncrypt = false)
        .then((_) => List.of(events));

    expect(sentByReturn, isEmpty);
    expect(await storedLocally(client, key), 'a value');
  });

  test(
      'Under the default preference, options that leave useRemoteAtServer '
      'unset route local as before', () async {
    const atSign = '@defaultlocal';
    final client = await clientFor(atSign);
    final key = selfKey(atSign);

    final sentByReturn = await client
        .put(key, 'a value',
            putRequestOptions: PutRequestOptions()..shouldEncrypt = false)
        .then((_) => List.of(events));

    expect(sentByReturn, isEmpty);
    expect(await storedLocally(client, key), 'a value');
  });

  test('Reading useRemoteAtServer on options that never set it gives false',
      () {
    expect(PutRequestOptions().useRemoteAtServer, isFalse);
    expect(GetRequestOptions().useRemoteAtServer, isFalse);
    expect(DeleteRequestOptions().useRemoteAtServer, isFalse);
  });
}
