/// Catalogue: features/at_client/request_options_unset_routing.feature
library;

import 'package:at_client/at_client_io.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/src/client/request_options.dart'
    show useRemoteAtServerIfSet;
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/no_keys.dart';
import 'test_utils/recording_remote.dart';
import 'test_utils/transport.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// Records the route a put hands its provider's prepare step.
class _PreparingProvider extends CryptoProvider implements PreparesWrites {
  final List<bool?> routes = [];

  @override
  String get id => 'preparing-provider';

  @override
  Future<void> prepareForWrite(CryptoContext context, AtKey atKey,
      {bool? useRemoteAtServer, String? sealToNamespace}) async {
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

/// Put options from outside the library, implementing the class.
class _ImplementedPutOptions implements PutRequestOptions {
  @override
  bool useRemoteAtServer = true;
  @override
  bool shouldEncrypt = false;
  @override
  bool alreadyEncrypted = false;
  @override
  String? cryptoProviderId;
  @override
  String? sealToNamespace;
  @override
  bool noCommit = false;
}

/// Put options from outside the library whose getter always asks for the
/// atServer.
class _AlwaysRemotePutOptions extends PutRequestOptions {
  @override
  bool get useRemoteAtServer => true;
}

/// Put options from outside the library that add a field and keep the
/// inherited useRemoteAtServer.
class _PlainSubclassPutOptions extends PutRequestOptions {
  String? appTag;
}

void main() {
  AtSignLogger.root_level = 'shout';

  late List<String> events;
  late List<String> commands;
  late Map<String, String> remoteData;
  late Map<String, Metadata> remoteMeta;

  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  setUp(() {
    events = [];
    commands = [];
    remoteData = {};
    remoteMeta = {};
  });

  /// A client of [atSign] over the recording remote, with [events] and
  /// [commands] emptied once it is built. Each test names its own atSign:
  /// `AtClientImpl.create` hands back a cached client for an atSign it has
  /// seen.
  Future<AtClientImpl> clientFor(String atSign,
      {RemoteLocalPref? remoteLocalPref,
      AtClientPreference? preference}) async {
    preference ??= AtClientPreference();
    if (remoteLocalPref != null) preference.remoteLocalPref = remoteLocalPref;
    final client = await AtClientImpl.create(atSign, 'testing', preference,
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: await refusingAtDirectory(),
            atKeysIo: noKeysFor(atSign),
            remoteSecondary: buildRecordingRemote(
                events: events,
                commands: commands,
                remoteData: remoteData,
                remoteMeta: remoteMeta),
            storage:
                InMemoryAtClientStorage(atSign: atSign, closedByClient: true))
        as AtClientImpl;
    addTearDown(client.stop);
    events.clear();
    commands.clear();
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

  test(
      'Under remoteOnly, a putMeta whose options leave useRemoteAtServer unset '
      'reaches the atServer before it returns', () async {
    const atSign = '@unsetputmeta';
    final client =
        await clientFor(atSign, remoteLocalPref: RemoteLocalPref.remoteOnly);
    final key = selfKey(atSign)..metadata.ttr = 120000;

    final sentByReturn = await client
        .putMeta(key, putRequestOptions: PutRequestOptions())
        .then((_) => List.of(commands));

    expect(sentByReturn,
        anyElement(allOf(startsWith('update:meta:'), contains('$key'))));
  });

  test(
      'Under remoteOnly, a delete or putMeta of a local: key stays on the '
      'device', () async {
    const atSign = '@localkey';
    final client =
        await clientFor(atSign, remoteLocalPref: RemoteLocalPref.remoteOnly);
    final key = AtKey.local('scratch', atSign, namespace: 'testing').build();
    await client.put(key, 'a value');
    final store = client.getLocalSecondary()!.keyStore!;
    expect(await storedLocally(client, key), 'a value',
        reason: 'the control: the record is on the device to delete');

    final sentByDelete = await client
        .delete(key, deleteRequestOptions: DeleteRequestOptions())
        .then((_) => List.of(events));

    expect(sentByDelete, isEmpty);
    await expectLater(
        store.get(key.toString()), throwsA(isA<KeyNotFoundException>()));

    key.metadata.ttr = 120000;
    final sentByPutMeta = await client
        .putMeta(key, putRequestOptions: PutRequestOptions())
        .then((_) => List.of(events));

    expect(sentByPutMeta, isEmpty);
    expect((await store.get(key.toString()))?.metaData?.ttr, 120000);
  });

  test(
      'Under remoteOnly, an encrypted put whose options leave useRemoteAtServer '
      'unset prepares and writes on the atServer', () async {
    const atSign = '@unsetencrypted';
    final provider = _PreparingProvider();
    final client = await clientFor(atSign,
        remoteLocalPref: RemoteLocalPref.remoteOnly,
        preference: AtClientPreference(posture: PqPosture.legacy)
          ..crypto = CryptoConfig(
              defaultProviderId: provider.id, providers: [provider]));
    final key = selfKey(atSign);

    final byReturn = await client
        .put(key, 'a value', putRequestOptions: PutRequestOptions())
        .then((_) => (routes: List.of(provider.routes), sent: List.of(events)));

    expect(byReturn.routes, [true]);
    expect(byReturn.sent, contains('update:$key'));
  });

  test(
      'An explicit useRemoteAtServer false on a get still reads local under '
      'remoteOnly', () async {
    const atSign = '@explicitlocalget';
    final client =
        await clientFor(atSign, remoteLocalPref: RemoteLocalPref.remoteOnly);
    final key = selfKey(atSign);
    await client.put(key, 'the local value',
        putRequestOptions: PutRequestOptions()
          ..useRemoteAtServer = false
          ..shouldEncrypt = false);
    final name = 'routed.testing$atSign';
    remoteData[name] = 'the atServer value';
    remoteMeta[name] = Metadata()..isEncrypted = false;
    events.clear();

    final byReturn = await client
        .get(key,
            getRequestOptions: GetRequestOptions()..useRemoteAtServer = false)
        .then((value) => (value: value.value, sent: List.of(events)));

    expect(byReturn.value, 'the local value');
    expect(byReturn.sent, isEmpty);
  });

  test(
      'Under remoteOnly, a noCommit put whose options leave useRemoteAtServer '
      'unset reaches the atServer', () async {
    const atSign = '@unsetnocommit';
    final client =
        await clientFor(atSign, remoteLocalPref: RemoteLocalPref.remoteOnly);
    final key = selfKey(atSign);

    final sentByReturn = await client
        .put(key, 'a value',
            putRequestOptions: PutRequestOptions()
              ..noCommit = true
              ..shouldEncrypt = false)
        .then((_) => List.of(commands));

    expect(sentByReturn,
        anyElement(allOf(startsWith('update:nc:'), contains('$key'))));
  });

  test(
      'Under remoteOnly, a noCommit putMeta reaches the atServer with noCommit',
      () async {
    const atSign = '@nocommitputmeta';
    final client =
        await clientFor(atSign, remoteLocalPref: RemoteLocalPref.remoteOnly);
    final key = selfKey(atSign)..metadata.ttr = 120000;

    final sentByReturn = await client
        .putMeta(key, putRequestOptions: PutRequestOptions()..noCommit = true)
        .then((_) => List.of(commands));

    expect(sentByReturn,
        anyElement(allOf(startsWith('update:meta:nc:'), contains('$key'))));
  });

  test('A noCommit putMeta that is not routed to the atServer is refused',
      () async {
    const atSign = '@nocommitputmetalocal';
    final client = await clientFor(atSign);
    final key = selfKey(atSign);
    await client.put(key, 'a value',
        putRequestOptions: PutRequestOptions()..shouldEncrypt = false);
    final store = client.getLocalSecondary()!.keyStore!;
    events.clear();
    key.metadata.ttr = 120000;

    await expectLater(
        client.putMeta(key,
            putRequestOptions: PutRequestOptions()..noCommit = true),
        throwsA(isA<IllegalArgumentException>()));

    expect(events, isEmpty);
    expect((await store.get(key.toString()))?.metaData?.ttr, isNot(120000));
  });

  group('options from outside the library', () {
    test(
        'Under remoteOnly, a put whose options subclass PutRequestOptions and '
        'leave useRemoteAtServer unset reaches the atServer', () async {
      const atSign = '@plainsubclass';
      final client =
          await clientFor(atSign, remoteLocalPref: RemoteLocalPref.remoteOnly);
      final key = selfKey(atSign);

      final sentByReturn = await client
          .put(key, 'a value',
              putRequestOptions: _PlainSubclassPutOptions()
                ..shouldEncrypt = false)
          .then((_) => List.of(events));

      expect(sentByReturn, contains('update:$key'));
      expect(useRemoteAtServerIfSet(_PlainSubclassPutOptions()), isNull);
      expect(
          useRemoteAtServerIfSet(
              _PlainSubclassPutOptions()..useRemoteAtServer = false),
          isFalse);
    });

    test('an object implementing PutRequestOptions is routed by its getter',
        () async {
      const atSign = '@implementedoptions';
      final client = await clientFor(atSign);
      final key = selfKey(atSign);

      final sentByReturn = await client
          .put(key, 'a value', putRequestOptions: _ImplementedPutOptions())
          .then((_) => List.of(events));

      expect(sentByReturn, contains('update:$key'));
    });

    test(
        'a PutRequestOptions subclass whose getter says true goes to the '
        'atServer', () async {
      const atSign = '@subclassedoptions';
      final client = await clientFor(atSign);
      final key = selfKey(atSign);

      final sentByReturn = await client
          .put(key, 'a value',
              putRequestOptions: _AlwaysRemotePutOptions()
                ..shouldEncrypt = false)
          .then((_) => List.of(events));

      expect(sentByReturn, contains('update:$key'));
    });
  });
}
