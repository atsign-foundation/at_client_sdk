import 'dart:io';

import 'package:at_client/at_client_io.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart' as auth_cli;
import 'package:test/test.dart';

import 'utils/at_client_cache.dart';
import 'utils/lifecycle.dart';
import 'utils/test_keys_dir.dart';

/// The CLI's enrollment commands against a real atServer: a request is
/// submitted through at_client, decided through `at_activate`, and the
/// keyfile it completes authenticates or not as the decision says.
///
/// Every authentication opens its own client and stops it afterwards, because
/// a client stays live in this process until stopped and a second open for
/// the same atSign is refused while one is — see [authenticateWithApkamKeys].
void main() {
  String atSign = '@sitaram🛠';
  String masterKeysFilePath = testKeysFile(atSign);
  String apkamKeysFilePath = testKeysFile(atSign, suffix: 'apkam');
  String passwordProtectedKeysFilePath =
      testKeysFile(atSign, suffix: 'apkam-password-protected');
  String passPhrase = 'abcd';
  final logger = AtSignLogger('E2E Test');

  // Runs once before all tests.
  setUpAll(() async {
    // Fetched cram key from the at_demos repo.
    await activateThroughCli(atSign,
        _settings(masterKeysFilePath, cramSecret: cramKeyMap[atSign]));
    // NOTE: the static client cache is keyed on `(atSign, enrollmentId)`
    // alone, so without this eviction the CLI commands below run against the
    // client the activation left behind rather than the one they ask for.
    await evictCachedAtClients();
    // Set SPP
    List<String> args = [
      'spp',
      '-s',
      'ABC123',
      '-a',
      atSign,
      '-r',
      'vip.ve.atsign.zone',
      '-k',
      masterKeysFilePath
    ];
    var res = await runCliCommand(args);
    // Zero indicates successful completion.
    expect(res, 0);
  });

  group('A group of tests to validate enrollment commands', () {
    /// The test verifies the following scenario's
    /// 1. Activates an atSign
    /// 2. Sets Semi Permanent Passcode
    /// 3. Submits an enrollment request
    /// 4. Approves the enrollment request
    /// 5. Performs authentication with the approved enrollment Id. Authentication should be successful.
    /// 6. Revokes the enrollment Id.
    /// 7. Performs authentication again with the revoked enrollment Id. Authentication fails this time.
    /// 8. Unrevoke the enrollment Id.
    /// 9. Performs authentication again with the unrevoked enrollment Id. Authentication should be successful.
    test(
        'A test to verify end-to-end flow of approve revoke unrevoke of an enrollment',
        () async {
      final settings = _settings(apkamKeysFilePath);

      // Submit enrollment request; the keyfile named holds it pending.
      final pending = await Atsign(atSign).enroll(
          otp: 'ABC123',
          app: 'wavi',
          device: 'local-device',
          namespaces: {'e2etest': 'rw'},
          keys: settings.keysFor(atSign),
          preference: settings.preference,
          lookUps: settings.lookUps,
          secondaryAddressFinder: settings.secondaryAddressFinder);
      String enrollmentId = pending.enrollmentId;
      logger.info(
          'Submitted enrollment successfully with enrollmentId: $enrollmentId');
      expect(enrollmentId.isNotEmpty, true);
      expect(File(apkamKeysFilePath).existsSync(), true,
          reason: 'the submission is on disk before anyone approves it');

      // Approve enrollment request
      List<String> args = [
        'approve',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-i',
        enrollmentId,
        '-k',
        masterKeysFilePath
      ];
      var res = await runCliCommand(args);
      expect(res, 0);
      logger.info('Approved enrollment with enrollmentId: $enrollmentId');

      // The approval completes the keyfile.
      await pending.awaitApproval();

      // Authenticate with APKAM keys
      expect(
          await authenticateWithApkamKeys(
              atSign, apkamKeysFilePath, enrollmentId),
          true);

      // Revoke the enrollment
      args = [
        'revoke',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-i',
        enrollmentId,
        '-k',
        masterKeysFilePath
      ];
      res = await runCliCommand(args);
      expect(res, 0);
      logger.info('Revoked enrollment with enrollmentId: $enrollmentId');

      // Perform authentication with revoked enrollmentId.
      //
      // Polled with a bound rather than asserted immediate: for a short window
      // after a revoke, a holder of the revoked keyfile can still authenticate,
      // because the atServer resolves an enrollment's state for PKAM through a
      // cache that revocation reaches on an eventual schedule. The bound is
      // what keeps this an assertion — if the credential never stops working,
      // this stays red.
      bool revokedStillAuthenticates = true;
      for (var i = 0; i < 20; i++) {
        revokedStillAuthenticates = await authenticateWithApkamKeys(
            atSign, apkamKeysFilePath, enrollmentId);
        if (!revokedStillAuthenticates) break;
        await Future<void>.delayed(Duration(milliseconds: 500));
      }
      expect(revokedStillAuthenticates, false,
          reason: 'a revoked enrollment must stop authenticating');

      // UnRevoke the enrollment
      args = [
        'unrevoke',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-i',
        enrollmentId,
        '-k',
        masterKeysFilePath
      ];
      res = await runCliCommand(args);
      expect(res, 0);
      logger.info('Un-Revoked enrollment with enrollmentId: $enrollmentId');

      // Perform authentication with the unrevoked enrollment-id.
      expect(
          await authenticateWithApkamKeys(
              atSign, apkamKeysFilePath, enrollmentId),
          true);
    });

    test('A test to verify password protected of atKeys file', () async {
      // The pass-phrase encrypts the atKeys file the enrollment writes.
      final settings =
          _settings(passwordProtectedKeysFilePath, passPhrase: passPhrase);

      // Submit enrollment request
      final pending = await Atsign(atSign).enroll(
          otp: 'ABC123',
          app: 'buzz',
          device: 'local-device',
          namespaces: {'e2etest': 'rw'},
          keys: settings.keysFor(atSign),
          preference: settings.preference,
          lookUps: settings.lookUps,
          secondaryAddressFinder: settings.secondaryAddressFinder);
      String enrollmentId = pending.enrollmentId;
      logger.info(
          'Submitted enrollment successfully with enrollmentId: $enrollmentId');
      expect(enrollmentId.isNotEmpty, true);

      // Approve enrollment request
      List<String> args = [
        'approve',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-i',
        enrollmentId,
        '-k',
        masterKeysFilePath
      ];
      var res = await runCliCommand(args);
      expect(res, 0);
      logger.info('Approved enrollment with enrollmentId: $enrollmentId');

      // The approval completes the keyfile, encrypted under the pass-phrase.
      await pending.awaitApproval();

      // Authenticate with APKAM keys
      expect(
          await authenticateWithApkamKeys(
              atSign, passwordProtectedKeysFilePath, enrollmentId,
              passPhrase: passPhrase),
          true);

      // Run list to ensure the pass-phase is indeed working as expected
      args = [
        'list',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-P',
        passPhrase,
        '-k',
        passwordProtectedKeysFilePath
      ];
      res = await runCliCommand(args);
      // Zero indicate successful completion.
      expect(res, 0);
    });
  });

  tearDownAll(() {
    // Keyfiles live under the test keys dir, which is purged per run; this
    // directory appears only when the CLI is given a relative local-secondary
    // path, hence the guard.
    final storage = Directory('storage');
    if (storage.existsSync()) storage.deleteSync(recursive: true);
  });
}

/// Whether the keys in [atKeysFilePath] authenticate [atSign] as
/// [enrollmentId], through a client opened for this call alone and stopped
/// before this returns.
///
/// A client stays live in this process until stopped, and a second open for
/// the same atSign is refused while one is; a keyfile the atServer refuses
/// answers false.
Future<bool> authenticateWithApkamKeys(
    String atSign, String atKeysFilePath, String enrollmentId,
    {String? passPhrase}) async {
  await evictCachedAtClients();
  final AtClient client;
  try {
    client = await openClient(
        atSign, _settings(atKeysFilePath, passPhrase: passPhrase));
  } on AtOpenRefusedException {
    return false;
  }
  final online = client.connection.current.isOnline;
  if (online) {
    expect(client.enrollmentId, enrollmentId,
        reason: 'the keyfile names the enrollment the client runs as');
  }
  await client.stop();
  return online;
}

auth_cli.EnrollerSettings _settings(String atKeysFilePath,
        {String? cramSecret, String? passPhrase}) =>
    auth_cli.EnrollerSettings(
        vePreference(namespace: 'buzz', cramSecret: cramSecret),
        atKeysFilePath: atKeysFilePath,
        passPhrase: passPhrase);
