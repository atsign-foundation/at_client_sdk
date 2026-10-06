@Timeout(Duration(minutes: 30))
@Tags(['upgrade'])
library;

import 'dart:async';
import 'dart:convert' show LineSplitter, base64Decode, jsonDecode, jsonEncode;
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/functional_storage.dart'
    show FunctionalStorage, FunctionalStorageBackend;
import 'package:at_lookup/at_lookup.dart' show AtLookUpException;
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show AtData;
import 'package:at_utils/at_logger.dart' show AtSignLogger, LoggingHandler;
import 'package:test/test.dart';
import 'package:upgrade_scenario/upgrade_scenario.dart';

import 'test_utils.dart';

/// Whether a store one at_client wrote still works after an app moves to this
/// tree's at_client, checked the same way for every arm.
///
/// An arm seeds a store with its own at_client — a released one runs in its
/// own process, since no process can hold two versions of a package — and
/// reports what it observes of it. This tree then opens that store and must:
///
/// - observe what the seeding version observed;
/// - deliver the notifications sent while no client was running, and push the
///   write the seeding client left behind;
/// - read back every record after writing it through the same `AtKey` that
///   read it, once with its value and once with a value of another shape;
/// - do all of that again after a restart;
/// - leave no record whose flags contradict its value, and log no warning.
///
/// The arm seeded by this tree is the control: anything it reports is not
/// about an upgrade.
void main() {
  if (FunctionalStorage.backendFromEnvironment() !=
      FunctionalStorageBackend.hive) {
    test('the upgrade check', () {},
        skip: 'every arm writes a Hive store, so the Hive run is the one that '
            'checks it');
    return;
  }
  final logs = _Warnings()..install();
  TestUtils.isolateStorage('upgrade_test');

  // NOTE: atSigns pkamLoad provisions and no other test uses, because every
  // arm leaves records and notifications behind on their atServers.
  const me = '@kevin🛠';
  const peer = '@purnima🛠';
  final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final storageRoot = Directory('test/hive/upgrade/$runId').absolute.path;

  ClientSpec specFor(String atSign, String namespace, String dir) => ClientSpec(
      atSign: atSign,
      namespace: namespace,
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      storagePath: '$storageRoot/$dir');

  Future<AtClient> open(ClientSpec spec) => connect(
      spec: spec,
      preference: upgradePreference(spec),
      attach: attachWithoutKeySource);

  late AtClient peerClient;

  setUpAll(() async {
    peerClient = await open(specFor(peer, 'upgpeer$runId', 'peer'));
  });

  tearDownAll(() async => peerClient.stop());

  for (final arm in _arms) {
    group('from ${arm.label}', () {
      final namespace = 'upg${arm.tag}$runId';
      final spec = specFor(me, namespace, arm.tag);
      late DateTime armStarted;
      Map<String, Object?>? seeded;
      AtClient? client;
      bool? pushedBeforeUpgrade;
      String keyOf(RecordSpec record) =>
          record.keyFor(me: me, peer: peer, namespace: namespace).toString();

      tearDownAll(() async => client?.stop());

      Future<void> notifyMe(String label) async {
        final key = AtKey()
          ..key = label
          ..namespace = namespace
          ..sharedBy = peer
          ..sharedWith = me;
        await peerClient.notificationService
            .notify(NotificationParams.forUpdate(key, value: label));
      }

      /// Opens this tree's client on the seeded store, subscribing before the
      /// monitor starts so the notification sent while no client ran is not
      /// delivered ahead of the subscription.
      Future<({AtClient client, Future<bool> delivered})> openExpecting(
          String label) async {
        final opened = await open(spec);
        final delivered = opened.notificationService
            .subscribe(regex: '$label\\.$namespace', shouldDecrypt: true)
            .first
            .timeout(const Duration(seconds: 90))
            .then((_) => true, onError: (_) => false);
        return (client: opened, delivered: delivered);
      }

      /// Asserts this tree observes what the seeding version did, apart from
      /// the differences the arm declares — each of which must still occur.
      Future<void> expectObservedAsSeeded() async {
        final found = _differences(seeded!['snapshot'],
            await snapshot(client!, me: me, peer: peer, namespace: namespace));
        final expected = arm.expected(me, peer);
        expect(found.where((d) => !expected.containsKey(d)), isEmpty);
        expect(expected.keys.where((d) => !found.contains(d)), isEmpty,
            reason: 'an expected difference that no longer occurs is stale');
      }

      test('seeds a store', () async {
        armStarted = DateTime.now();
        final peerItems = await peerClient.collection<String>(
            collectionNamespace(namespace), itemLifetime);
        await peerItems.create(
            obj: 'their item', id: peerItemId, sharedWith: {me.toAtsign()});
        expect(await syncUntilInSync(peerClient), isTrue,
            reason: 'the peer item must be on its atServer before the seed '
                'looks for it');

        seeded = await arm.seed(spec, peer);
        final facts = Map.of(seeded!['facts'] as Map);
        final cursors = facts.remove('syncCursors');
        expect(
            facts,
            {
              'syncedBeforeReceipt': true,
              'peerItemSeen': true,
              'notificationReceived': true,
              'synced': true,
            },
            reason: 'every later check reads what the seed wrote; one that '
                'did not run makes them meaningless');
        expect(cursors, ['local:lastreceivedservercommitid.$namespace$me'],
            reason: 'a store with no lifecycle marker counts as having been '
                'online when it holds a sync cursor by this name, which '
                '`open_test.dart` seeds as ${arm.label} would have written it');
      });

      test('observes what the seeding version observed', () async {
        expect(seeded, isNotNull, reason: 'the seed did not run');
        pushedBeforeUpgrade = await _onServer(me, keyOf(pending));
        await notifyMe('gapone');
        final opened = await openExpecting('gapone');
        client = opened.client;

        final local = catalogue.firstWhere((r) => r.kind == RecordKind.local);
        final asSeeded =
            await client!.getLocalSecondary()!.keyStore!.get(keyOf(local));
        expect(asSeeded?.metaData?.isEncrypted, arm.encryptsLocalRecords,
            reason: 'the store must hold what ${arm.label} writes for a local '
                'record before anything here rewrites it, or the checks below '
                'are about some other store');
        await expectObservedAsSeeded();
        expect(await opened.delivered, isTrue,
            reason: 'a notification sent while no client ran is delivered '
                'when one starts, from the watermark the store holds');
      });

      test('syncs, and pushes what the seeding client left', () async {
        expect(client, isNotNull, reason: 'the upgraded client did not open');
        expect(pushedBeforeUpgrade, isFalse,
            reason: 'the seeding client must stop with its last write still '
                'unpushed, or the push checked below says nothing about this '
                'tree');
        for (final round in ['first', 'second']) {
          expect(await syncUntilInSync(client!), isTrue,
              reason: 'the $round sync after the upgrade did not complete');
        }
        final onServer = await client!.get(
            pending.keyFor(me: me, peer: peer, namespace: namespace),
            getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
        expect(onServer.value, pending.value);
        expect(await _onServer(me, keyOf(pending)), isTrue,
            reason: 'the lookup that found the write missing before the '
                'upgrade must find it now, or its "missing" meant nothing');
      });

      test('reads every record back after writing it through its own key',
          () async {
        expect(client, isNotNull, reason: 'the upgraded client did not open');
        final failures = <String>[];
        var settling = true;
        for (final record in catalogue) {
          AtKey fresh() =>
              record.keyFor(me: me, peer: peer, namespace: namespace);
          final key = fresh();
          try {
            final original = (await client!.get(key)).value;
            final writes = [
              (original, true),
              (_otherShape(original), true),
              (original, true),
              if (record.kind == RecordKind.local) (original, false),
            ];
            for (final (value, encrypt) in writes) {
              await client!.put(key, value,
                  putRequestOptions: PutRequestOptions()
                    ..shouldEncrypt = encrypt);
              final read = (await client!.get(fresh())).value;
              if (jsonEncode(read) != jsonEncode(value)) {
                failures.add('${record.name}: wrote ${jsonEncode(value)}, '
                    'read ${jsonEncode(read)}');
              }
              // NOTE: each write is pushed before the next, so no write
              // replaces one still in flight; that race is not this check's.
              if (settling) {
                settling = await syncUntilInSync(client!,
                    timeout: const Duration(seconds: 30));
                if (!settling) {
                  failures.add('${record.name}: sync stopped settling');
                }
              }
            }
          } catch (e) {
            failures.add('${record.name}: $e');
          }
        }
        final store = client!.getLocalSecondary()!.keyStore!;
        for (final record
            in catalogue.where((r) => r.kind == RecordKind.local)) {
          if ((await store.get(keyOf(record)))?.metaData?.isEncrypted !=
              false) {
            failures.add('${record.name}: stored flagged encrypted after a '
                'write that stores a local value as given');
          }
        }
        expect(failures, isEmpty);
      });

      test('survives a restart', () async {
        expect(client, isNotNull, reason: 'the upgraded client did not open');
        await client!.stop();
        await notifyMe('gaptwo');
        final opened = await openExpecting('gaptwo');
        client = opened.client;

        expect(await opened.delivered, isTrue,
            reason: 'the watermark the upgraded client wrote must read back');
        expect(await syncUntilInSync(client!), isTrue);
        await expectObservedAsSeeded();
      });

      test('leaves no record whose flags contradict its value', () async {
        expect(client, isNotNull, reason: 'the upgraded client did not open');
        final store = client!.getLocalSecondary()!.keyStore!;
        final keys = await (await store.getKeys()).toList();
        final ours = keys
            .where((k) => k.startsWith('local:') || k.contains('.$namespace@'))
            .toList();
        expect(ours, isNotEmpty, reason: 'the scan found none of the records');

        final violations = <String>[];
        for (final key in ours) {
          final data = await store.get(key);
          final contradiction = _contradiction(data);
          if (contradiction != null) violations.add('$key: $contradiction');
          try {
            await client!.get(AtKey.fromString(key));
          } catch (e) {
            violations.add('$key: unreadable, $e');
          }
        }
        expect(violations, isEmpty);
      });

      test('logs no warning', () {
        expect(logs.since(armStarted), isEmpty);
      });
    });
  }
}

/// One store-writing version of at_client.
class _Arm {
  final String label;

  /// Its part of the namespace and of the storage directory.
  final String tag;

  /// Seeds the store at the spec's path and reports the facts and the
  /// snapshot, as `bin/seed.dart` prints them.
  final Future<Map<String, Object?>> Function(ClientSpec spec, String peer)
      seed;

  /// Each snapshot difference this tree is meant to show against this arm,
  /// spelled as `_differences` reports it, with the reason it is meant.
  final Map<String, String> Function(String me, String peer) expected;

  /// Whether this version stores a `local:` record encrypted, as every
  /// release before 3.15 did.
  final bool encryptsLocalRecords;

  const _Arm(this.label, this.tag, this.seed,
      {required this.encryptsLocalRecords, this.expected = _none});
}

Map<String, String> _none(String me, String peer) => const {};

final _arms = [
  _Arm('this tree', 'tree', _seedHere, encryptsLocalRecords: false),
  _Arm('at_client 3.14.0', 'v3140', _seedReleased('3.14.0'),
      encryptsLocalRecords: true),
  // NOTE: the same release over the persistence, crypto and commons versions
  // it shipped with, so a change in what those store is in the comparison.
  _Arm('at_client 3.14.0 as built on its release day', 'v3140rd',
      _seedReleased('3.14.0-release-day'),
      encryptsLocalRecords: true),
  _Arm('at_client 3.15.0-rc3', 'rc3', _seedReleased('3.15.0-rc3'),
      encryptsLocalRecords: false,
      expected: (me, peer) => {
            '/items/$peer:$peerItemId/readBy: [] -> ["$me"]':
                'at_client 3.15.0-rc3 does not count a read receipt its own '
                    'reader sent once the item is read afresh',
            '/items/$peer:$peerItemId/wasMarkedReadByMe: false -> true':
                'the same receipt, asked about directly',
          }),
];

Future<Map<String, Object?>> _seedHere(ClientSpec spec, String peer) async {
  final client = await connect(
      spec: spec,
      preference: upgradePreference(spec),
      attach: attachWithoutKeySource);
  final facts = await seed(client,
      me: spec.atSign, peer: peer, namespace: spec.namespace);
  final observed = await snapshot(client,
      me: spec.atSign, peer: peer, namespace: spec.namespace);
  await writePending(client,
      me: spec.atSign, peer: peer, namespace: spec.namespace);
  await client.stop();
  return {'facts': facts, 'snapshot': observed};
}

Future<Map<String, Object?>> Function(ClientSpec, String) _seedReleased(
        String version) =>
    (ClientSpec spec, String peer) async {
      final dir = '${Directory.current.path}/../upgrade/released/$version';
      // NOTE: the lockfile is committed and the pin exact, so this resolves
      // the released build rather than whatever is newest.
      final pubGet =
          await Process.run('dart', ['pub', 'get'], workingDirectory: dir);
      expect(pubGet.exitCode, 0,
          reason:
              'pub get failed in $dir:\n${pubGet.stdout}\n${pubGet.stderr}');

      final result = await Process.run(
          'dart',
          [
            'run',
            'upgrade_scenario:seed',
            '--atsign',
            spec.atSign,
            '--peer',
            peer,
            '--namespace',
            spec.namespace,
            '--root-domain',
            spec.rootDomain,
            '--root-port',
            '${spec.rootPort}',
            '--storage',
            spec.storagePath,
          ],
          workingDirectory: dir);
      final report = const LineSplitter()
          .convert('${result.stdout}')
          .where((l) => l.startsWith('##UPGRADE##'))
          .toList();
      expect(report, hasLength(1),
          reason: 'at_client $version printed no report.\n'
              'exit ${result.exitCode}\n'
              'stdout: ${result.stdout}\nstderr: ${result.stderr}');
      return (jsonDecode(report.single.substring('##UPGRADE##'.length)) as Map)
          .cast<String, Object?>();
    };

/// Whether [atSign]'s atServer holds [key], asked over a connection of its
/// own rather than through a client that might push the record first.
Future<bool> _onServer(String atSign, String key) async {
  final lookUp = TestUtils.lookUpAs(atSign,
      AtEncryptionKeysLoader.getInstance().createAtKeysFromDemoKeys(atSign));
  try {
    final answer = await lookUp.executeCommand('llookup:$key\n', auth: true);
    return answer != null && answer.trim() != 'data:null';
  } on AtLookUpException catch (e) {
    if (e.errorCode == 'AT0015') return false;
    rethrow;
  } finally {
    await lookUp.close();
  }
}

/// A value of a different shape from [value]: a binary one grows a byte, and
/// text loses its newlines, which decide whether it is stored encoded.
Object _otherShape(Object? value) => value is List<int>
    ? [...value, 7]
    : '${'$value'.replaceAll('\n', ' ')} (rewritten)';

/// Each place [after] differs from [before], as `path: before -> after`.
List<String> _differences(Object? before, Object? after, [String path = '']) {
  if (before is Map && after is Map) {
    return [
      for (final key in {...before.keys, ...after.keys})
        ..._differences(before[key], after[key], '$path/$key'),
    ];
  }
  if (before is List && after is List && before.length == after.length) {
    return [
      for (var i = 0; i < before.length; i++)
        ..._differences(before[i], after[i], '$path[$i]'),
    ];
  }
  final was = jsonEncode(before);
  final now = jsonEncode(after);
  return was == now ? const [] : ['$path: $was -> $now'];
}

/// What [data]'s metadata claims about its value that the value contradicts,
/// or null.
String? _contradiction(AtData? data) {
  final value = data?.data;
  final metaData = data?.metaData;
  if (value is! String || metaData == null) return null;
  final providerId = metaData.appMetadata?.providerId;
  final legacy = providerId == null || providerId == 'legacy';
  if (metaData.isEncrypted == true && legacy && !_legacyCiphertext(value)) {
    return 'flagged encrypted, but the value is not legacy ciphertext';
  }
  if (metaData.encoding == 'base64') {
    try {
      base64Decode(value);
    } on FormatException {
      return 'flagged base64, but the value does not decode';
    }
  }
  return null;
}

/// Legacy ciphertext is AES with PKCS7 padding, base64 encoded.
bool _legacyCiphertext(String value) {
  try {
    final length = base64Decode(value).length;
    return length > 0 && length % 16 == 0;
  } on FormatException {
    return false;
  }
}

/// Every warning or worse logged in this isolate, passed on to the handler
/// that was installed before it.
class _Warnings implements LoggingHandler {
  final _records = <({DateTime at, String text})>[];
  late final LoggingHandler _next;

  void install() {
    _next = AtSignLogger.defaultLoggingHandler;
    AtSignLogger.defaultLoggingHandler = this;
    AtSignLogger.root_level = 'info';
  }

  /// [record] is `dynamic` so this file need not import `package:logging`.
  @override
  void call(dynamic record) {
    _next(record);
    if (record.level.value >= 900) {
      _records.add((
        at: DateTime.now(),
        text: '${record.level.name} ${record.loggerName}: ${record.message}'
      ));
    }
  }

  List<String> since(DateTime start) => [
        for (final r in _records)
          if (!r.at.isBefore(start)) r.text
      ];
}
