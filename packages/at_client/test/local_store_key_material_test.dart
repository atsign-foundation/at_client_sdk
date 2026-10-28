import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator;
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';
import 'test_utils/hive_store.dart';

/// What a client built without a keyfile does with the key material it found
/// in its own local store: says what it found, and authenticates with its PKAM
/// key.
///
/// The three logging arms are different situations, not three levels of the
/// same one: an empty store is what every client looks like before onboarding,
/// while a store holding one keypair and not the other is a state onboarding
/// does not produce.
void main() {
  final logs = RecordedLogs();
  const atSign = '@storelog';
  final root = '${Directory.current.path}/test/hive_storelog';

  setUpAll(() => logs.installOn());

  AtClientPreference pref(String path) => AtClientPreference()
    ..isLocalStoreRequired = true
    ..syncRegex = ''
    ..hiveStoragePath = path;

  /// Builds a client on its own store, seeds it with [seed], then builds a
  /// SECOND client on that same store and returns it, running — the second is
  /// the one under test, because the client reads its store's key material
  /// during construction and can only read what was already there.
  Future<AtClientImpl> runningOverStore(
      String name, Map<String, String> seed) async {
    final path = '$root/$name';
    AtClientImpl.atClientInstanceMap.clear();
    final seeder = await AtClientImpl.create(atSign, 'wavi', pref(path),
        storage: hiveStoreFor(atSign, pref(path)));
    seeder.syncService = MockSyncService();
    for (final entry in seed.entries) {
      await seeder.getLocalSecondary()!.putValue(entry.key, entry.value);
    }
    await (seeder as AtClientImpl).stop();

    AtClientImpl.atClientInstanceMap.clear();
    logs.records.clear();
    final client = await AtClientImpl.create(atSign, 'wavi', pref(path),
        storage: hiveStoreFor(atSign, pref(path)));
    client.syncService = MockSyncService();
    return client as AtClientImpl;
  }

  Future<void> clientOverStore(String name, Map<String, String> seed) async =>
      (await runningOverStore(name, seed)).stop();

  final pkam = RsaKeyPair.generate();
  final encryption = RsaKeyPair.generate();

  tearDownAll(() async {
    await HiveInstances.closeAll();
    await Hive.close();
    final d = Directory(root);
    if (d.existsSync()) d.deleteSync(recursive: true);
  });

  test('a store holding neither keypair says so once, at info', () async {
    await clientOverStore('empty', const {});

    expect(logs.at('INFO').where((m) => m.contains('holds no key material')),
        hasLength(1),
        reason: 'once, not once per keypair: what a reader acts on is what '
            'the client ended up holding, not which of two lookups missed');
    expect(logs.at('WARNING').where((m) => m.contains('key')), isEmpty,
        reason: 'an un-onboarded store is the ordinary state, so it must not '
            'compete with the warnings that mean something is wrong. Saw: '
            '${logs.at('WARNING')}');
  });

  test('a store holding one keypair and not the other is a WARNING', () async {
    await clientOverStore('partial', {
      AtConstants.atPkamPublicKey: pkam.atPublicKey.publicKey,
      AtConstants.atPkamPrivateKey: pkam.atPrivateKey.privateKey,
    });

    final warnings =
        logs.at('WARNING').where((m) => m.contains('but not the other'));
    expect(warnings, hasLength(1),
        reason: 'onboarding does not produce half a store, so this one is '
            'broken and the client fails at whichever key it needs first');
    expect(warnings.single, contains('a PKAM'),
        reason: 'and it names which half is present, because that decides '
            'what still works. Saw: $warnings');
    expect(logs.at('INFO').where((m) => m.contains('holds no key material')),
        isEmpty,
        reason: 'a partial store is not an empty one');
  });

  test('a store holding both says nothing', () async {
    await clientOverStore('both', {
      AtConstants.atPkamPublicKey: pkam.atPublicKey.publicKey,
      AtConstants.atPkamPrivateKey: pkam.atPrivateKey.privateKey,
      '${AtConstants.atEncryptionPublicKey}$atSign':
          encryption.atPublicKey.publicKey,
      AtConstants.atEncryptionPrivateKey: encryption.atPrivateKey.privateKey,
    });

    expect(logs.at('WARNING').where((m) => m.contains('but not the other')),
        isEmpty,
        reason: 'the control: a complete store must stay quiet, or the arm '
            'above would go red for any store at all');
    expect(logs.at('INFO').where((m) => m.contains('holds no key material')),
        isEmpty);
  });

  test(
      'a client with no keyfile authenticates with the PKAM key its local '
      'store holds', () async {
    final client = await runningOverStore('authenticates', {
      AtConstants.atPkamPublicKey: pkam.atPublicKey.publicKey,
      AtConstants.atPkamPrivateKey: pkam.atPrivateKey.privateKey,
      '${AtConstants.atEncryptionPublicKey}$atSign':
          encryption.atPublicKey.publicKey,
      AtConstants.atEncryptionPrivateKey: encryption.atPrivateKey.privateKey,
    });
    addTearDown(client.stop);
    const challenge = '_9e8169dc-5618-44ec-ab43-1a5b2144c581$atSign'
        ':c3d345fc-5691-4f90-bc34-17cba31f060f';

    Future<bool> signsWithStoredKey(AtAuthenticator authenticate) async {
      final executor = _RecordingExecutor(['data:$challenge', 'data:success']);
      expect(await authenticate(executor), isTrue);
      final command = executor.sent.last;
      return RsaSignatureAlgo.rsa2048().verifyBytes(
          Uint8List.fromList(utf8.encode(challenge)),
          signature: base64Decode(
              command.substring(command.lastIndexOf(':') + 1).trim()),
          publicKey: base64Decode(pkam.atPublicKey.publicKey));
    }

    expect(
        await signsWithStoredKey(
            client.buildRemoteSecondary().atLookUp.authenticator!),
        isTrue,
        reason: 'its own connection');
    expect(
        await signsWithStoredKey(
            SyncServiceImpl.remoteSecondaryFor(client).atLookUp.authenticator!),
        isTrue,
        reason: 'and its sync\'s');
  });
}

/// Answers each command with the next of [replies] and records what was sent.
class _RecordingExecutor implements AtCommandExecutor {
  final List<String> sent = [];
  final List<String> replies;

  _RecordingExecutor(this.replies);

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    return replies.removeAt(0);
  }
}
