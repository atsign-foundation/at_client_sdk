/// Catalogue: features/at_client/get_meta_metadata_only.feature
library;

import 'dart:convert';

import 'package:at_client/at_client_io.dart';
import 'package:at_client/memory.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show AtData, AtMetaData;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

void main() {
  AtSignLogger.root_level = 'shout';

  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  late List<String> atServerCommands;
  late List<String> localCommands;
  late Future<String> Function(VerbBuilder builder) atServer;
  Future<String> Function(VerbBuilder builder)? localFailure;

  setUp(() {
    atServerCommands = [];
    localCommands = [];
    atServer = (builder) async =>
        throw KeyNotFoundException('${builder.buildCommand().trim()} holds '
            'no record');
    localFailure = null;
  });

  /// A client of [atSign] over in-memory storage and a scripted atServer,
  /// which records each command it is sent in [atServerCommands] and answers
  /// it with [atServer]. Each test names its own atSign, or stops the client
  /// before the next one asks for it, since `AtClientImpl.create` hands back a
  /// cached client for an atSign it has seen.
  Future<AtClientImpl> clientFor(String atSign,
      {RemoteLocalPref? remoteLocalPref}) async {
    final preference = AtClientPreference();
    if (remoteLocalPref != null) preference.remoteLocalPref = remoteLocalPref;
    final remote = MockRemoteSecondary();
    when(() => remote.sync(any(), regex: any(named: 'regex')))
        .thenAnswer((_) async => null);
    when(() => remote.executeVerb(any())).thenAnswer((inv) {
      final builder = inv.positionalArguments.first as VerbBuilder;
      atServerCommands.add(builder.buildCommand().trim());
      return atServer(builder);
    });
    final client = await AtClientImpl.create(atSign, 'testing', preference,
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: await refusingAtDirectory(),
            atKeysIo: noKeysFor(atSign),
            remoteSecondary: remote,
            storage:
                InMemoryAtClientStorage(atSign: atSign, closedByClient: true))
        as AtClientImpl;
    addTearDown(client.stop);
    atServerCommands.clear();
    return client;
  }

  /// Runs [call] with [client]'s local storage watched: each command it is
  /// sent is recorded in [localCommands], and answered by [localFailure] when
  /// that is set, else by local storage itself.
  Future<T> watchingLocal<T>(
      AtClientImpl client, Future<T> Function() call) async {
    final local = client.localSecondary!;
    final watched = MockLocalSecondary();
    when(() => watched.executeVerb(any())).thenAnswer((inv) {
      final builder = inv.positionalArguments.first as VerbBuilder;
      localCommands.add(builder.buildCommand().trim());
      return localFailure?.call(builder) ?? local.executeVerb(builder);
    });
    client.localSecondary = watched;
    try {
      return await call();
    } finally {
      client.localSecondary = local;
    }
  }

  AtKey selfKey(AtClientImpl client, String name) => AtKey()
    ..key = name
    ..namespace = 'testing'
    ..sharedBy = client.getCurrentAtSign()
    ..metadata = (Metadata()..namespaceAware = true);

  /// Puts a record under [key] straight into [client]'s local storage.
  Future<void> holdLocally(AtClientImpl client, AtKey key,
          {String value = 'a value', AtMetaData? metadata}) =>
      client.getLocalSecondary()!.keyStore!.put(
          key.toString(),
          AtData()
            ..data = value
            ..metaData = metadata ?? AtMetaData());

  /// A metadata answer from the atServer, as it sends one: nulls removed.
  String metadataAnswer(Map<String, dynamic> fields) =>
      'data:${jsonEncode(fields)}';

  Matcher isLookupFailure() => isA<AtClientException>().having(
      (e) => e is AtKeyNotFoundException, 'is AtKeyNotFoundException', isFalse);

  GetRequestOptions atServerOptions() =>
      GetRequestOptions()..useRemoteAtServer = true;
  GetRequestOptions localOptions() =>
      GetRequestOptions()..useRemoteAtServer = false;

  test(
      'Given a record in local storage whose value this client cannot decrypt, when getMeta is called with no options, then its metadata is returned and nothing is sent to the atServer',
      () async {
    final client = await clientFor('@gmcannotopen');
    final key = selfKey(client, 'cannotopen');
    await holdLocally(client, key,
        value: 'not-ciphertext',
        metadata: AtMetaData()
          ..isEncrypted = true
          ..ttr = 3600);

    final metadata = await watchingLocal(
        client, () => client.getMeta(selfKey(client, 'cannotopen')));

    expect(metadata?.ttr, 3600);
    expect(metadata?.isEncrypted, isTrue);
    expect(localCommands, ['llookup:meta:$key']);
    expect(atServerCommands, isEmpty);
    await expectLater(
        client.get(selfKey(client, 'cannotopen')), throwsA(isA<AtException>()),
        reason: 'the control: the record is there and its value cannot be '
            'opened, so a value read fails where the metadata lookup answers');
  });

  test(
      'Given a record only the atServer holds, when getMeta is called with useRemoteAtServer true, then llookup:meta reaches the atServer and its metadata is returned',
      () async {
    final client = await clientFor('@gmonlyremote');
    final key = selfKey(client, 'remoteonly');
    atServer = (builder) async => metadataAnswer({'ttl': 100, 'ttr': 30});

    final metadata = await watchingLocal(client,
        () => client.getMeta(key, getRequestOptions: atServerOptions()));

    expect(atServerCommands, ['llookup:meta:$key']);
    expect(localCommands, isEmpty);
    expect(metadata?.ttl, 100);
    expect(metadata?.ttr, 30);
  });

  test(
      'Given a client whose preference reads from the atServer only, when getMeta is called with options that leave useRemoteAtServer unset, then the lookup reaches the atServer',
      () async {
    final client = await clientFor('@gmunsetremote',
        remoteLocalPref: RemoteLocalPref.remoteOnly);
    final key = selfKey(client, 'held');
    atServer = (builder) async => metadataAnswer({'ttl': 100});

    await client.getMeta(key,
        getRequestOptions: GetRequestOptions()..bypassCache = true);

    expect(atServerCommands, ['llookup:meta:$key']);
  });

  test(
      'Given a client whose preference reads from the atServer only, when getMeta is called with useRemoteAtServer false, then only local storage is asked',
      () async {
    final client = await clientFor('@gmexplicitlocal',
        remoteLocalPref: RemoteLocalPref.remoteOnly);
    final key = selfKey(client, 'held');
    await holdLocally(client, key, metadata: AtMetaData()..ttr = 3600);

    final metadata = await watchingLocal(
        client, () => client.getMeta(key, getRequestOptions: localOptions()));

    expect(metadata?.ttr, 3600);
    expect(localCommands, ['llookup:meta:$key']);
    expect(atServerCommands, isEmpty);
  });

  const kindOutline =
      'Given a key of each kind, when getMeta is called with no options, then the metadata-only lookup for that kind is sent to the secondary get would use';
  for (final row in [
    ('self', 'k.ns@alice', 'llookup:meta:k.ns@alice', 'local storage'),
    (
      'shared by @alice with @bob',
      '@bob:k.ns@alice',
      'llookup:meta:@bob:k.ns@alice',
      'local storage'
    ),
    (
      'public of @alice',
      'public:k.ns@alice',
      'llookup:meta:public:k.ns@alice',
      'local storage'
    ),
    (
      'cached from @bob',
      'cached:@alice:k.ns@bob',
      'llookup:meta:cached:@alice:k.ns@bob',
      'local storage'
    ),
    (
      'shared with @alice by @bob',
      '@alice:k.ns@bob',
      'lookup:meta:k.ns@bob',
      'the atServer'
    ),
    (
      'public of @bob',
      'public:k.ns@bob',
      'plookup:meta:k.ns@bob',
      'the atServer'
    ),
  ]) {
    final (kind, key, command, secondary) = row;
    test('$kindOutline: $kind, $command, $secondary', () async {
      final client = await clientFor('@alice');

      try {
        await watchingLocal(
            client, () => client.getMeta(AtKey.fromString(key)));
      } on AtKeyNotFoundException {
        // NOTE: neither side holds the record; only where the lookup went is
        // asserted.
      }

      final local = secondary == 'local storage';
      expect(local ? localCommands : atServerCommands, [command]);
      expect(local ? atServerCommands : localCommands, isEmpty);
    });
  }

  test(
      'Given a local: key, when getMeta is called with useRemoteAtServer true, then the lookup stays on the device',
      () async {
    final client = await clientFor('@alice');
    final key = AtKey.local('k', '@alice', namespace: 'ns').build();
    await holdLocally(client, key, metadata: AtMetaData()..ttr = 3600);

    final metadata = await watchingLocal(client,
        () => client.getMeta(key, getRequestOptions: atServerOptions()));

    expect(localCommands, ['llookup:meta:local:k.ns@alice']);
    expect(atServerCommands, isEmpty);
    expect(metadata?.ttr, 3600);
  });

  const othersKeyOutline =
      'Given a key shared with the client by another Atsign, when getMeta is called with useRemoteAtServer false, then the lookup still goes to the atServer';
  for (final row in [
    ('shared with @alice', '@alice:k.ns@bob', 'lookup:meta:k.ns@bob'),
    ('public', 'public:k.ns@bob', 'plookup:meta:k.ns@bob'),
  ]) {
    final (kind, key, command) = row;
    test('$othersKeyOutline: $kind, $command', () async {
      final client = await clientFor('@alice');
      atServer = (builder) async => metadataAnswer({'ttl': 100});

      await watchingLocal(
          client,
          () => client.getMeta(AtKey.fromString(key),
              getRequestOptions: localOptions()));

      expect(atServerCommands, [command]);
      expect(localCommands, isEmpty);
    });
  }

  test(
      'Given a key of another Atsign, when getMeta is called with bypassCache, then the lookup asks the atServer to skip its cached copy',
      () async {
    final client = await clientFor('@alice');
    atServer = (builder) async => metadataAnswer({'ttl': 100});

    await client.getMeta(AtKey.fromString('public:k.ns@bob'),
        getRequestOptions: GetRequestOptions()..bypassCache = true);

    expect(atServerCommands, ['plookup:bypassCache:true:meta:k.ns@bob']);
  });

  const notVisibleOutline =
      'Given a record that is held but not visible now, when getMeta is called, then it returns null';
  final inTenMinutes = DateTime.now().toUtc().add(const Duration(minutes: 10));
  final aMinuteAgo =
      DateTime.now().toUtc().subtract(const Duration(minutes: 1));
  for (final row in [
    (
      'local storage',
      'not yet available',
      AtMetaData()..availableAt = inTenMinutes
    ),
    (
      'local storage',
      'past its expiry and not yet removed',
      AtMetaData()..expiresAt = aMinuteAgo
    ),
    ('the atServer', 'not yet available', null),
    ('the atServer', 'past its expiry and not yet removed', null),
  ]) {
    final (leg, state, metadata) = row;
    test('$notVisibleOutline: $leg, $state', () async {
      final client = await clientFor('@alice');
      final key = selfKey(client, 'hidden');
      final local = leg == 'local storage';
      if (local) {
        await holdLocally(client, key, metadata: metadata);
      } else {
        // NOTE: both states are scripted with the same data:null answer.
        atServer = (builder) async => 'data:null';
      }

      final answer = await watchingLocal(
          client,
          () => client.getMeta(selfKey(client, 'hidden'),
              getRequestOptions: local ? localOptions() : atServerOptions()));

      expect(answer, isNull);
      expect(local ? localCommands : atServerCommands, ['llookup:meta:$key'],
          reason: 'the control: the record was looked up where it is held');
    });
  }

  const notFoundOutline =
      'Given no record under a key, when getMeta is called, then it throws AtKeyNotFoundException';
  for (final leg in ['local storage', 'the atServer']) {
    test('$notFoundOutline: $leg', () async {
      final client = await clientFor('@alice');
      final local = leg == 'local storage';

      await expectLater(
          watchingLocal(
              client,
              () => client.getMeta(selfKey(client, 'absent'),
                  getRequestOptions:
                      local ? localOptions() : atServerOptions())),
          throwsA(isA<AtKeyNotFoundException>()));
      expect((local ? localCommands : atServerCommands).length, 1);
    });
  }

  const failureOutline =
      'Given a lookup that fails without an answer about the record, when getMeta is called, then it throws AtClientException';
  for (final row in <(String, String, Exception)>[
    (
      'the atServer',
      "the atServer's address refuses the connection",
      SecondaryConnectException('@alice: unable to connect to atServer on '
          '127.0.0.1:53942 - SocketException: Connection refused')
    ),
    (
      'the atServer',
      'the atDirectory refuses the connection',
      AtException('Connecting to 127.0.0.1:53942 : SocketException: '
          'Connection refused')
    ),
    (
      'the atServer',
      'the atServer answers AT0009 for an enrollment without access',
      AtExceptionUtils.get(
          'AT0009',
          'Connection with enrollment ID e1 is not authorized to llookup '
              'key: failing.testing@alice')
    ),
    (
      'the atServer',
      'the atServer refuses the session with AT0401',
      AtExceptionUtils.get(
          'AT0401',
          'Failed connecting to @alice. error:AT0401-Exception: pkam '
              'authentication failed')
    ),
    (
      'the atServer',
      'the atServer does not answer in time',
      AtExceptionUtils.get('AT0014', 'Request timed out')
    ),
    (
      'local storage',
      "the enrollment has no access to the key's namespace",
      UnAuthorizedException('Cannot perform llookup on '
          'failing.testing@alice due to insufficient privilege')
    ),
  ]) {
    final (leg, cause, failure) = row;
    test('$failureOutline: $leg, $cause', () async {
      final client = await clientFor('@alice');
      final local = leg == 'local storage';
      if (local) {
        localFailure = (_) async => throw failure;
      } else {
        atServer = (_) async => throw failure;
      }

      await expectLater(
          watchingLocal(
              client,
              () => client.getMeta(selfKey(client, 'failing'),
                  getRequestOptions:
                      local ? localOptions() : atServerOptions())),
          throwsA(isLookupFailure()));
      expect((local ? localCommands : atServerCommands).length, 1);
    });
  }

  const stoppedOutline =
      'Given a client that has stopped, when getMeta is called, then it throws StoppedException';
  for (final leg in ['local storage', 'the atServer']) {
    test('$stoppedOutline: $leg', () async {
      final client = await clientFor('@alice');
      final local = leg == 'local storage';
      await client.stop();
      atServer = (_) async =>
          throw StoppedException('the connection for @alice has been stopped');

      await expectLater(
          watchingLocal(
              client,
              () => client.getMeta(selfKey(client, 'held'),
                  getRequestOptions:
                      local ? localOptions() : atServerOptions())),
          throwsA(isA<StoppedException>()));
    });
  }

  const notMetadataOutline =
      'Given an atServer answer that is not metadata, when getMeta is called, then it throws AtClientException and returns nothing';
  for (final row in [
    ('a JSON list', 'data:[]'),
    ('a JSON string', 'data:"x"'),
    ('text that is not JSON', 'data:{bad'),
    (
      'an object with an expiresAt that is not a date',
      'data:{"expiresAt":"x"}'
    ),
    ('an object whose ttl is a string', 'data:{"ttl":"5"}'),
  ]) {
    final (body, answer) = row;
    test('$notMetadataOutline: $body', () async {
      final client = await clientFor('@alice');
      atServer = (_) async => answer;

      await expectLater(
          client.getMeta(selfKey(client, 'garbled'),
              getRequestOptions: atServerOptions()),
          throwsA(isLookupFailure()));
      expect(atServerCommands, hasLength(1));
    });
  }

  test(
      'Given an atServer answer that claims the key is public and cached, when getMeta is called with a self key, then the metadata says neither',
      () async {
    final client = await clientFor('@gmforgedflags');
    atServer = (_) async => metadataAnswer({
          'isPublic': true,
          'isCached': true,
          'ttl': 100,
          'ttr': 30,
          'isEncrypted': true,
          'ivNonce': 'aXZOb25jZQ==',
          'sharedKeyEnc': 'c2hhcmVk',
        });

    final metadata = await client.getMeta(selfKey(client, 'claimed'),
        getRequestOptions: atServerOptions());

    expect(metadata?.isPublic, isFalse);
    expect(metadata?.isCached, isFalse);
    expect(metadata?.ttl, 100);
    expect(metadata?.ttr, 30);
    expect(metadata?.isEncrypted, isTrue);
    expect(metadata?.ivNonce, 'aXZOb25jZQ==');
    expect(metadata?.sharedKeyEnc, 'c2hhcmVk');
  });

  test(
      'Given a public key of another Atsign, when getMeta is called, then the returned metadata is public and not cached',
      () async {
    final client = await clientFor('@alice');
    atServer = (_) async =>
        metadataAnswer({'isPublic': false, 'isCached': true, 'ttl': 100});

    final metadata = await client.getMeta(AtKey.fromString('public:k.ns@bob'));

    expect(metadata?.isPublic, isTrue);
    expect(metadata?.isCached, isFalse);
    expect(atServerCommands, ['plookup:meta:k.ns@bob']);
  });

  test(
      'Given an enrollment without access to a namespace, when getMeta is asked for a record in it that is held and for one that is missing, then both fail the same way',
      () async {
    final client = await clientFor('@alice');
    final held = AtKey.fromString('held.ns@alice');
    final missing = AtKey.fromString('missing.ns@alice');
    atServer = (builder) async {
      final key = (builder as LLookupVerbBuilder).buildKey();
      // NOTE: the refusal is scripted before any record lookup.
      if (key.endsWith('.ns@alice')) {
        throw AtExceptionUtils.get('AT0009',
            'Connection with enrollment ID e1 is not authorized to llookup key: $key');
      }
      return key == held.toString()
          ? metadataAnswer({'ttl': 100})
          : throw KeyNotFoundException('$key does not exist in keystore');
    };

    final failures = <String, Object>{};
    for (final key in [held, missing]) {
      try {
        await client.getMeta(key, getRequestOptions: atServerOptions());
      } catch (e) {
        failures['$key'] = e;
      }
    }

    expect(failures.values, everyElement(isLookupFailure()));
    expect(failures.keys, ['$held', '$missing']);
    String shape(String key) => '${failures[key]}'.replaceAll(key, '<key>');
    expect(shape('$held'), shape('$missing'));
  });

  test(
      'Given a record this client can open, when getMeta is called, then it returns the Metadata that get returns for the key',
      () async {
    final client = await clientFor('@gmopenable');
    await client.put(selfKey(client, 'open'), 'a value',
        putRequestOptions: PutRequestOptions()..shouldEncrypt = false);

    final fromGet = (await client.get(selfKey(client, 'open'))).metadata;
    final fromGetMeta = await client.getMeta(selfKey(client, 'open'));

    expect(fromGet, isNotNull);
    expect(fromGetMeta, fromGet);
  });

  test(
      'Given a key with metadata of its own, when getMeta is called, then the key keeps that metadata',
      () async {
    final client = await clientFor('@gmkeepsmeta');
    await holdLocally(client, selfKey(client, 'kept'),
        metadata: AtMetaData()..ttr = 1000);
    final key = selfKey(client, 'kept')..metadata.ttr = 777;

    final metadata = await client.getMeta(key);

    expect(metadata?.ttr, 1000,
        reason: 'the control: the stored record has a ttr of its own');
    expect(key.metadata.ttr, 777);
  });

  test(
      'Given an invalid key, when getMeta is called, then it throws AtKeyException and sends nothing',
      () async {
    final client = await clientFor('@alice');

    await expectLater(
        watchingLocal(
            client,
            () => client.getMeta(AtKey()
              ..key = ''
              ..sharedBy = '@alice')),
        throwsA(isA<AtKeyException>()));
    expect(localCommands, isEmpty);
    expect(atServerCommands, isEmpty);
  });
}
