import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';

/// What a client says about the key material it found in its own local store.
///
/// The three arms are different situations, not three levels of the same one:
/// an empty store is what every client looks like before onboarding, while a
/// store holding one keypair and not the other is a state onboarding does not
/// produce.
void main() {
  final logs = RecordedLogs();
  const atSign = '@chopslog';
  final root = '${Directory.current.path}/test/hive_chopslog';

  setUpAll(() => logs.installOn());

  AtClientPreference pref(String path) => AtClientPreference()
    ..isLocalStoreRequired = true
    ..syncRegex = ''
    ..hiveStoragePath = path
    ..commitLogPath = '$path/commit';

  /// Builds a client on its own store, seeds it with [seed], then builds a
  /// SECOND client on that same store — the second is the one under test,
  /// because `_createAtChops` runs during construction and can only read what
  /// was already there.
  Future<void> clientOverStore(String name, Map<String, String> seed) async {
    final path = '$root/$name';
    AtClientImpl.atClientInstanceMap.clear();
    final seeder = await AtClientImpl.create(atSign, 'wavi', pref(path));
    seeder.syncService = MockSyncService();
    for (final entry in seed.entries) {
      await seeder.getLocalSecondary()!.putValue(entry.key, entry.value);
    }
    await (seeder as AtClientImpl).stop();

    AtClientImpl.atClientInstanceMap.clear();
    logs.records.clear();
    final client = await AtClientImpl.create(atSign, 'wavi', pref(path));
    client.syncService = MockSyncService();
    await (client as AtClientImpl).stop();
  }

  final pkam = AtChopsUtil.generateAtPkamKeyPair();
  final encryption = AtChopsUtil.generateAtEncryptionKeyPair();

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
}
