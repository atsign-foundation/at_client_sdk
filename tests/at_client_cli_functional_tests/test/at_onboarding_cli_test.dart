import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client_io.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
import 'package:at_lookup/at_lookup_io.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart' as auth_cli;
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'utils/at_client_cache.dart';
import 'utils/lifecycle.dart';
import 'utils/test_keys_dir.dart';
import 'utils/virtualenv_ports.dart';

Map<String, bool> keysCreatedMap = {};

void main() {
  AtSignLogger.root_level = 'WARNING';

  // These group of tests run on docker container with only cram key available on secondary
  // Perform cram auth and update keys manually.
  Future<void> createKeys(String atSign) async {
    if (keysCreatedMap.containsKey(atSign)) {
      return;
    }
    // CRAM is the authenticator; the first command that needs it runs it.
    final atLookup = secureSocketLookUps()(
        atSign: atSign,
        rootDomain: AtRootDomain('vip.ve.atsign.zone', virtualenvRootPort),
        authenticator:
            authenticatorForCramSecret(atSign, at_demos.cramKeyMap[atSign]!));
    var command =
        'update:privatekey:at_pkam_publickey ${at_demos.pkamPublicKeyMap[atSign]}\n';
    var response = await atLookup.executeCommand(command, auth: true);
    expect(response, 'data:-1');
    command =
        'update:public:publickey$atSign ${at_demos.encryptionPublicKeyMap[atSign]}\n';
    await atLookup.executeCommand(command, auth: true);
    keysCreatedMap[atSign] = true;
    await atLookup.close();
  }

  // NOTE: every test in this group and the next drives a pre-enrollment atSign
  // — `_createKeys` installs the flat `at_pkam_publickey` and nothing else —
  // so each names `PqPosture.legacy`. At a post-quantum posture the client
  // gives such an atSign its first enrollment on its first start, rewriting
  // the keyfile and replacing the PKAM key these tests read back. Name it on
  // every call: one atSign in one process holds one posture, so a client
  // cached at another posture is refused rather than reused.
  group('A group of tests to assert on authenticate functionality', () {
    test('A test to verify authentication is successful with .atKeys file',
        () async {
      String atSign = '@alice🛠';
      await createKeys(atSign);
      final settings = settingsFor(atSign, posture: PqPosture.legacy);
      await generateAtKeysFile(atSign, settings.atKeysFilePath);
      final client = await openClient(atSign, settings);
      expect(client.connection.current.isOnline, true);
    });

    test(
        'A test to verify update and llookup verbs with authenticated atLookup instance',
        () async {
      String atSign = '@alice🛠';
      await createKeys(atSign);
      final settings = settingsFor(atSign, posture: PqPosture.legacy);
      await generateAtKeysFile(atSign, settings.atKeysFilePath);
      final client = await openOnline(atSign, settings);
      AtLookUp? atLookUp = client.getRemoteSecondary()?.atLookUp;
      AtKey key = AtKey();
      key.key = 'testKey1';
      await atLookUp?.executeVerb(UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = key.key
          ..sharedBy = atSign)
        ..value = 'value1');
      String? response = await atLookUp?.executeVerb(LLookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = key.key
          ..sharedBy = atSign));
      expect('data:value1', response);
    });

    test(
        'A test to authenticate and atSign and invoke AtClient put and get methods',
        () async {
      String atSign = '@eve🛠';
      await createKeys(atSign);
      final settings = settingsFor(atSign, posture: PqPosture.legacy);
      await generateAtKeysFile(atSign, settings.atKeysFilePath);
      final atClient = await openOnline(atSign, settings);
      AtKey key = AtKey();
      key.key = 'testKey3';
      key.namespace = 'wavi';
      await atClient.put(key, 'value3');
      AtValue response = await atClient.get(key);
      expect('value3', response.value);
    });

    tearDown(() async {
      await tearDownFunc();
    });
  });

  group('A group of tests to assert the client answers the keyfile\'s keys',
      () {
    String atSign = '@eve🛠'.trim();
    final settings = settingsFor(atSign, posture: PqPosture.legacy);
    AtClient? atClient;

    test(
        'A test to authenticate atSign and verify the PKAM keys and encryption keys the client answers are the keyfile\'s',
        () async {
      await generateAtKeysFile(atSign, settings.atKeysFilePath);
      await createKeys(atSign);
      atClient = await openClient(atSign, settings);
      expect(true, atClient!.connection.current.isOnline);

      expect(at_demos.pkamPrivateKeyMap[atSign],
          await atClient?.getLocalSecondary()?.getPkamPrivateKey());

      expect(at_demos.pkamPublicKeyMap[atSign],
          await atClient?.getLocalSecondary()?.getPkamPublicKey());

      expect(at_demos.encryptionPrivateKeyMap[atSign],
          await atClient?.getLocalSecondary()?.getEncryptionPrivateKey());

      String? encryptionPublicKey =
          await atClient?.getLocalSecondary()?.getEncryptionPublicKey(atSign);
      expect(at_demos.encryptionPublicKeyMap[atSign], encryptionPublicKey);
    });

    tearDown(() async {
      await tearDownFunc();
    });
  });

  group('A group of tests to verify activation', () {
    test('Activate and verify failure modes', () async {
      String atSign = '@egcovidlab🛠';
      final settings = settingsFor(atSign);
      File atKeysFile = File(settings.atKeysFilePath);

      final rootDomain = AtRootDomain(
          settings.preference.rootDomain, settings.preference.rootPort);
      Future<bool> activated() async {
        final lookUp = secureSocketLookUps()(
            atSign: atSign, rootDomain: rootDomain, authenticator: null);
        try {
          return (await checkAtSignServer(lookUp, atSign)).state ==
              AtSignServerState.activated;
        } finally {
          await lookUp.close();
        }
      }

      // The protocol half alone: the keys are minted and filed, and the CRAM
      // secret is left on the atServer, so the atDirectory does not yet
      // report the atSign activated.
      final activationLookUp = secureSocketLookUps()(
          atSign: atSign, rootDomain: rootDomain, authenticator: null);
      try {
        await activateAtSign(
            atSign: atSign,
            cramSecret: settings.preference.cramSecret!,
            keys: settings.keysFor(atSign),
            signingAlgo: settings.preference.authenticationKeyAlgorithm,
            rootDomain: rootDomain,
            completeActivation: false,
            atLookUp: activationLookUp,
            awaitProvisioning: true);
      } finally {
        await activationLookUp.close();
      }
      expect(await activated(), false);
      expect(await atKeysFile.exists(), true);
      await atKeysFile.delete();

      // The whole activation, as `at_activate onboard` runs it.
      await auth_cli.activate(atSign, settings);
      expect(await activated(), true);
      expect(await atKeysFile.exists(), true);
      await atKeysFile.delete();

      // Again: refused before anything is minted.
      await expectLater(
          auth_cli.activate(atSign, settings),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.message == 'atsign $atSign is already activated')));

      // With a keyfile in place: refused as an overwrite.
      await atKeysFile.create(recursive: true);
      await expectLater(auth_cli.activate(atSign, settings),
          throwsA(predicate((dynamic e) => e is AtException)));
    });

    tearDown(() async {
      await tearDownFunc();
    });
  });

  // This test exiting with status 0 is skipping the rest of the functional tests
  // Skipping this test until the issue can be resolved
  group('A group of tests to verify activate_cli', () {
    String atSign = '@murali🛠';
    final settings = settingsFor(atSign);
    test(
        'A test to verify atSign is activated and .atKeys file is generated using activate_cli',
        () async {
      List<String> args = [
        // Named: leaving it out still runs onboard, but with a deprecation
        // warning.
        'onboard',
        '-a',
        atSign,
        '-c',
        at_demos.cramKeyMap[atSign]!,
        '-r',
        'vip.ve.atsign.zone',
        // Without -k the CLI writes the generated keyfile to the home
        // directory's real keys dir.
        '-k',
        settings.atKeysFilePath,
      ];
      // perform activation of atSign
      await runCliCommand(args);

      /// ToDo: test should NOT exit with status 0 after activation is complete
      /// Exiting with status 0 is ideal behaviour, but for the sake of the test we need to be
      /// able to run the following assertions.

      // Authenticate atSign with the .atKeys file generated via the activate_cli tool
      expect(await File(settings.atKeysFilePath).exists(), true);
      // NOTE: the activation left a client in the static cache, keyed without
      // the storage path these settings ask for. Without the eviction the
      // open below reuses that client and the settings do nothing.
      await evictCachedAtClients();
      final client = await openClient(atSign, settings);
      expect(client.connection.current.isOnline, true);
    });

    tearDownAll(() async {
      await tearDownFunc();
    });
  });
}

/// The settings these tests share: [atSign]'s keyfile in the test keys dir,
/// its store under `storage/`, and its demo CRAM secret. Omitted, [posture]
/// is the SDK default.
auth_cli.EnrollerSettings settingsFor(String atSign, {PqPosture? posture}) {
  atSign = AtUtils.fixAtSign(atSign);
  return auth_cli.EnrollerSettings(
      vePreference(posture: posture, cramSecret: at_demos.cramKeyMap[atSign]),
      atKeysFilePath: testKeysFile(atSign),
      storagePath: 'storage/hive/client');
}

Future<void> generateAtKeysFile(String atSign, String filePath) async {
  atSign = AtUtils.fixAtSign(atSign);
  Map<String, String?> atKeysMap = <String, String?>{
    'aesPkamPublicKey': EncryptionUtil.encryptValue(
        at_demos.pkamPublicKeyMap[atSign]!, at_demos.aesKeyMap[atSign]!),
    'aesPkamPrivateKey': EncryptionUtil.encryptValue(
        at_demos.pkamPrivateKeyMap[atSign]!, at_demos.aesKeyMap[atSign]!),
    'aesEncryptPublicKey': EncryptionUtil.encryptValue(
        at_demos.encryptionPublicKeyMap[atSign]!, at_demos.aesKeyMap[atSign]!),
    'aesEncryptPrivateKey': EncryptionUtil.encryptValue(
        at_demos.encryptionPrivateKeyMap[atSign]!, at_demos.aesKeyMap[atSign]!),
    'selfEncryptionKey': at_demos.aesKeyMap[atSign],
    atSign: at_demos.aesKeyMap[atSign]
  };

  File file = File(filePath);
  if (!(file.existsSync())) {
    file = await file.create(recursive: true);
  }
  var atKeysFile = await file.open(mode: FileMode.write);
  atKeysFile.writeStringSync(jsonEncode(atKeysMap));
  await atKeysFile.close();
}

Future<void> tearDownFunc() async {
  // NOTE: stopped before the directory goes, or a client still holding a store
  // in it fails its own release when it is stopped later.
  await evictCachedAtClients();
  bool isExists = await Directory('storage/').exists();
  if (isExists) {
    Directory('storage/').deleteSync(recursive: true);
  }
}
