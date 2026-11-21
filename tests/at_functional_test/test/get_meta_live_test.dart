@Tags(['pq'])
library;

import 'package:at_client/at_client_io.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// What an atServer answers to getMeta's metadata-only lookups: null for a
/// record it holds but does not serve yet, not found for one it lacks, the
/// same refusal for a held and a missing record outside an enrollment's
/// namespaces, and the metadata of another Atsign's shared and public keys.
///
/// Catalogue: features/at_client/get_meta_metadata_only.feature
void main() {
  TestUtils.isolateStorage('get_meta_live_test');
  final runId = DateTime.now().microsecondsSinceEpoch;
  final namespace = 'gm$runId';
  final granted = 'gmg$runId';
  const tenMinutes = 600000;
  const anHour = 3600000;
  late String alice;
  late String bob;
  late AtClient aliceClient;
  late AtClient bobClient;

  final atServer = GetRequestOptions()..useRemoteAtServer = true;
  AtKey self(String id, [String? ns]) =>
      AtKey.fromString('$id.${ns ?? namespace}$alice');

  setUpAll(() async {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(alice, AtKeys());
    aliceClient = (await TestUtils.initAtClient(alice, namespace,
            atKeysIo: keysIo, posture: legacyPlusPqProviders))
        .atClient;
    await AtClientSecretSharing.forClient(aliceClient).register();

    final loader = AtEncryptionKeysLoader.getInstance();
    bobClient = await Atsign(bob).open(
        keys:
            InMemoryAtKeysIo.holding(bob, loader.createAtKeysFromDemoKeys(bob)),
        preference: TestUtils.getPreference(bob, posture: PqPosture.legacy)
          ..namespace = namespace,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: TestUtils.atDirectory,
        namespace: namespace,
        storage: TestUtils.storageFor(bob));
    await loader.setEncryptionKeys(bobClient, bob);
  });

  tearDownAll(() async {
    await bobClient.stop();
  });

  test(
      'Given a record that is held but not visible now, when getMeta is called, then it returns null: the atServer, not yet available',
      () async {
    final hidden = self('hidden$runId')
      ..metadata = (Metadata()..ttb = tenMinutes);
    await aliceClient.put(hidden, 'v',
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);

    expect(
        await aliceClient.getMeta(self('hidden$runId'),
            getRequestOptions: atServer),
        isNull);
  });

  test(
      'Given no record under a key, when getMeta is called, then it throws AtKeyNotFoundException: the atServer',
      () async {
    await expectLater(
        aliceClient.getMeta(self('absent$runId'), getRequestOptions: atServer),
        throwsA(isA<AtKeyNotFoundException>()));
  });

  test(
      'Given an enrollment without access to a namespace, when getMeta is asked for a record in it that is held and for one that is missing, then both fail the same way',
      () async {
    final held = self('held$runId');
    final missing = self('missing$runId');
    await aliceClient.put(held, 'v',
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);
    expect(
        await aliceClient.getMeta(self('held$runId'),
            getRequestOptions: atServer),
        isNotNull,
        reason: 'the control: the owner reads the held record');

    final scoped = await enrolAndAuthenticate(
      approver: aliceClient,
      atSign: alice,
      namespace: granted,
      preference: TestUtils.getPreference(alice, posture: PqPosture.legacy),
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      deviceName: 'getmeta-$runId',
      storage: TestUtils.storage,
      namespaces: {granted: 'rw'},
    );
    try {
      final failures = <String, Object>{};
      for (final key in [held, missing]) {
        try {
          await scoped.client
              .getMeta(AtKey.fromString('$key'), getRequestOptions: atServer);
        } catch (e) {
          failures['$key'] = e;
        }
      }

      expect(failures.keys, ['$held', '$missing']);
      expect(
          failures.values,
          everyElement(allOf(
              isA<AtClientException>(), isNot(isA<AtKeyNotFoundException>()))));
      String shape(String key) => '${failures[key]}'.replaceAll(key, '<key>');
      expect(shape('$held'), shape('$missing'));
      await expectLater(
          scoped.client.getMeta(self('missing$runId', granted),
              getRequestOptions: atServer),
          throwsA(isA<AtKeyNotFoundException>()),
          reason: 'the control: in its own namespace the enrollment is told '
              'the record is missing');
    } finally {
      await scoped.stop();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
      "Given a key shared with the client by another Atsign, when getMeta is called, then it returns that Atsign's metadata for the key",
      () async {
    final shared = AtKey.fromString('$alice:shared$runId.$namespace$bob')
      ..metadata = (Metadata()..ttl = anHour);
    await bobClient.put(shared, 'v',
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);

    final metadata = await aliceClient
        .getMeta(AtKey.fromString('$alice:shared$runId.$namespace$bob'));

    expect(metadata?.ttl, anHour);
    expect(metadata?.isPublic, isFalse);
  });

  test(
      "Given a public key of another Atsign, when getMeta is called, then it returns that Atsign's metadata for the key",
      () async {
    final public = AtKey.fromString('public:public$runId.$namespace$bob')
      ..metadata = (Metadata()
        ..isPublic = true
        ..ttl = anHour);
    await bobClient.put(public, 'v',
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);

    final metadata = await aliceClient
        .getMeta(AtKey.fromString('public:public$runId.$namespace$bob'));

    expect(metadata?.ttl, anHour);
    expect(metadata?.isPublic, isTrue);
  });
}
