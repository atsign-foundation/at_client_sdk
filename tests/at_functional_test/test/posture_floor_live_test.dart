@Tags(['pq'])
library;

import 'package:at_client/at_client_io.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger, LoggingHandler;
import 'package:test/test.dart';

import 'test_utils.dart';

/// A client never runs below the posture floor its keyfile's key material
/// sets, met against a live atServer.
///
/// Catalogue: features/at_client/posture_floor.feature
void main() {
  final logs = _Logs()..install();
  TestUtils.isolateStorage('posture_floor_live_test');
  // NOTE: run-unique, so each namespace below is minted by this run.
  final runId = DateTime.now().microsecondsSinceEpoch;
  final loader = AtEncryptionKeysLoader.getInstance();
  late String alice;
  late String bob;

  setUpAll(() {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
  });

  /// A client of [atSign] over [keys], configured [posture] and working in
  /// [namespace], on [storage].
  Future<AtClientImpl> open(String atSign, AtKeysIo keys, PqPosture posture,
      String namespace, AtClientStorage storage) async {
    final client = await Atsign(atSign).open(
        keys: keys,
        preference: TestUtils.getPreference(atSign, posture: posture)
          ..namespace = namespace,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: TestUtils.atDirectory,
        namespace: namespace,
        storage: storage) as AtClientImpl;
    addTearDown(client.stop);
    await loader.setEncryptionKeys(client, atSign);
    await client.pqBootstrap?.startupComplete;
    return client;
  }

  InMemoryAtKeysIo demoKeys(String atSign) =>
      InMemoryAtKeysIo.holding(atSign, loader.createAtKeysFromDemoKeys(atSign));

  /// The kid of the namespace key [atSign] publishes at [namespace].
  Future<String> publishedKid(
          AtClient client, String atSign, String namespace) async =>
      (await PublishedNskeyKeyRing(client).currentPublic(atSign, namespace))!
          .nskeyKid;

  test(
      'A client whose keyfile holds a namespace-key private runs at pqReady '
      'at least', () async {
    final namespace = 'k1$runId.sensor';
    final keys = demoKeys(alice);
    final storage = TestUtils.storageForPrincipal(alice, 'key-material');
    final minter =
        await open(alice, keys, PqPosture.pqReady, namespace, storage);
    expect((await minter.ensureReachable(namespace)).holdsPrivate, isTrue,
        reason: 'the precondition: a namespace key is published at '
            '$namespace and its private filed in this keyfile');
    final kid = await publishedKid(minter, alice, namespace);
    expect(
        await NskeyPrivateFiling(keysIo: keys, atSign: alice)
            .read(namespace, kid),
        isNotNull,
        reason: "the precondition: the keyfile holds the namespace key's "
            'private');
    await minter.stop();

    final started = DateTime.now();
    final client =
        await open(alice, keys, PqPosture.legacy, namespace, storage);

    expect(
        logs.since(started, 'WARNING'),
        anyElement(contains(
            'is configured PqPosture.legacy and is raised to its pqReady '
            'floor')),
        reason: 'it warns that it runs at pqReady, since its keyfile holds a '
            'namespace-key private');
    final reachable = await client.ensureReachable(namespace);
    expect(reachable.outcome, AtReachability.alreadyReachable,
        reason: 'its namespace key is published already');
    expect(reachable.holdsPrivate, isTrue,
        reason: 'it holds the private its keyfile carries, so it can open '
            'what peers seal there');

    final sierra = await open(bob, demoKeys(bob), PqPosture.pqActive, namespace,
        TestUtils.storageFor(bob));
    final sealed = AtKey.fromString('$alice:reading.$namespace$bob');
    await sierra.put(sealed, 'sealed by $bob',
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);
    final AtValue read;
    try {
      read = await client.get(AtKey.fromString(sealed.toString()));
    } on Exception catch (e) {
      fail("it opens what $bob seals to its namespace key, and reading it "
          'threw $e');
    }
    expect(read.value, 'sealed by $bob',
        reason: "it opens what $bob seals to its namespace key");
    expect(read.metadata?.appMetadata?.additional?['ckNs'], namespace,
        reason: "what it opened was sealed under its key at $namespace, not "
            'with legacy encryption');
  }, timeout: Timeout(Duration(minutes: 4)));
}

/// Keeps every record at [AtSignLogger]'s root level or above, with when it
/// was logged, and passes each on.
class _Logs implements LoggingHandler {
  final _records = <({DateTime at, int level, String text})>[];
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
    _records.add(
        (at: DateTime.now(), level: record.level.value, text: record.message));
  }

  static const _levels = {'INFO': 800, 'WARNING': 900};

  /// What was logged at [level] or above since [start].
  List<String> since(DateTime start, String level) => [
        for (final r in _records)
          if (!r.at.isBefore(start) && r.level >= _levels[level]!) r.text
      ];
}
