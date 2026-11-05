import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart'
    show
        authenticatorFor,
        authenticatorForCramSecret,
        authenticatorForPrivateKey;
import 'package:at_chops/at_chops.dart' show MlDsa65KeyPair;
import 'package:at_client/at_client_io.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart' as auth_cli;
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
import 'package:at_lookup/at_lookup.dart' show AtLookUp, AtLookUpException;
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'utils/at_client_cache.dart';
import 'utils/enrollment_operations.dart';
import 'utils/lifecycle.dart';
import 'utils/test_keys_dir.dart';
import 'utils/virtualenv_ports.dart';

/// A retrofit whose keyfile refuses the save after the atServer approved it:
/// the new enrollment is revoked where the predecessor may revoke, the refusal
/// is reported where it may not, and the next start retrofits again.
///
/// ⚠️ One-shot, destructive server state: `@kevin🛠` and `@sameeraja🛠` are
/// this file's alone.
void main() {
  AtSignLogger.root_level = 'WARNING';

  final String rootPredecessor = AtUtils.fixAtSign('@kevin🛠');
  final String scopedAtSign = AtUtils.fixAtSign('@sameeraja🛠');
  const rootDomain = 'vip.ve.atsign.zone';
  const scopedNamespace = 'r2ns';

  final logs = _CapturedLogs();
  late LoggingHandler handlerBefore;

  setUpAll(() {
    handlerBefore = AtSignLogger.defaultLoggingHandler;
    AtSignLogger.defaultLoggingHandler = logs;
  });

  tearDownAll(() async {
    AtSignLogger.defaultLoggingHandler = handlerBefore;
    await evictCachedAtClients();
    final storage = Directory('storage/');
    if (storage.existsSync()) storage.deleteSync(recursive: true);
  });

  auth_cli.EnrollerSettings settingsFor(String atSign, PqPosture? posture,
          {required String keyfile, required String store}) =>
      auth_cli.EnrollerSettings(vePreference(posture: posture),
          atKeysFilePath: keyfile, storagePath: 'storage/hive/$atSign/$store');

  /// A client of [atSign] on [keys], every live client of it stopped first.
  Future<AtClient> openWith(String atSign, auth_cli.EnrollerSettings settings,
      WrittenAtKeysIo keys) async {
    for (final live in AtClientImpl.liveClientsFor(atSign)) {
      await live.stop();
    }
    final client = await Atsign(atSign).open(
        keys: keys,
        preference: settings.preference,
        storage: settings.storageFor(atSign),
        lookUps: settings.lookUps,
        secondaryAddressFinder: settings.secondaryAddressFinder);
    AtClientManager.getInstance().use(client);
    return client;
  }

  /// A `scan` on [client]'s own connection, which the atServer answers only
  /// once that connection has authenticated.
  Future<String?> authenticatedNoop(AtClient client) => client
      .getRemoteSecondary()!
      .atLookUp
      .executeCommand('scan\n', auth: true);

  group('a retrofit whose keyfile refuses the save after approval', () {
    /// Leaves [atSign] holding only the legacy flat PKAM keypair, which the
    /// atServer answers as `primary`, and its encryption public key.
    Future<void> makeLegacyAtSign(String atSign) async {
      final atLookup = secureSocketLookUps()(
          atSign: atSign,
          rootDomain: AtRootDomain(rootDomain, virtualenvRootPort),
          authenticator:
              authenticatorForCramSecret(atSign, at_demos.cramKeyMap[atSign]!));
      expect(
          await atLookup.executeCommand(
              'update:privatekey:at_pkam_publickey '
              '${at_demos.pkamPublicKeyMap[atSign]}\n',
              auth: true),
          'data:-1',
          reason: 'the fixture: without the flat credential the atSign '
              'cannot authenticate at all');
      await atLookup.executeCommand(
          'update:public:publickey$atSign '
          '${at_demos.encryptionPublicKeyMap[atSign]}\n',
          auth: true);
      await atLookup.close();
    }

    /// The roster of [atSign], read over a bare `pkam:` as `primary`.
    Future<Map<String, dynamic>> rosterAsPrimary(String atSign) async {
      final atLookup = secureSocketLookUps()(
          atSign: atSign,
          rootDomain: AtRootDomain(rootDomain, virtualenvRootPort),
          authenticator: authenticatorForPrivateKey(
              atSign, at_demos.pkamPrivateKeyMap[atSign]!));
      expect(await atLookup.pkamAuthenticate(), true);
      final response = await atLookup.executeCommand(
          (EnrollVerbBuilder()
                ..operation = EnrollOperationEnum.list
                ..enrollmentStatusFilter = [
                  EnrollmentStatus.approved,
                  EnrollmentStatus.revoked,
                  EnrollmentStatus.pending,
                ])
              .buildCommand(),
          auth: true);
      await atLookup.close();
      return jsonDecode(response!.replaceFirst('data:', ''))
          as Map<String, dynamic>;
    }

    Map<String, dynamic> recordOf(Map<String, dynamic> roster, String id) =>
        roster[roster.keys.singleWhere((k) => k.startsWith(id),
            orElse: () => fail('the roster names no record for $id; it '
                'holds ${roster.keys}'))] as Map<String, dynamic>;

    /// The keyfile a legacy onboarding would have written, naming no
    /// enrollment.
    Future<void> writeLegacyKeyfile(String atSign, String path) async {
      final aes = at_demos.aesKeyMap[atSign]!;
      final file = File(path);
      if (!file.existsSync()) await file.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'aesPkamPublicKey': EncryptionUtil.encryptValue(
            at_demos.pkamPublicKeyMap[atSign]!, aes),
        'aesPkamPrivateKey': EncryptionUtil.encryptValue(
            at_demos.pkamPrivateKeyMap[atSign]!, aes),
        'aesEncryptPublicKey': EncryptionUtil.encryptValue(
            at_demos.encryptionPublicKeyMap[atSign]!, aes),
        'aesEncryptPrivateKey': EncryptionUtil.encryptValue(
            at_demos.encryptionPrivateKeyMap[atSign]!, aes),
        'selfEncryptionKey': aes,
        atSign: aes,
      }));
    }

    test(
        'R1: a root predecessor revokes the enrollment it could not save, and '
        'the next start retrofits', () async {
      await makeLegacyAtSign(rootPredecessor);
      final keyfile = testKeysFile(rootPredecessor);
      await writeLegacyKeyfile(rootPredecessor, keyfile);
      final settings = settingsFor(rootPredecessor, PqPosture.pqReady,
          keyfile: keyfile, store: 'r1');
      final keys = _RefusesFirstRetrofitSave(settings.keysFor(rootPredecessor));

      await evictCachedAtClients();
      final failedFrom = logs.retrofitFailures.length;
      final first = await openWith(rootPredecessor, settings, keys);

      final orphan = keys.refusedSaveNamed;
      expect(orphan, allOf(isNotNull, isNot('primary')),
          reason: 'R1: the save the keyfile refused names the enrollment the '
              'atServer approved');
      expect(keys.writes.take(2), ['update', 'flush refused'],
          reason: 'R1: the write check before the request took its write, '
              'and the refusal came from the save after approval');
      expect(first.enrollmentId, 'primary',
          reason: 'R1: a retrofit that did not complete leaves the client on '
              'its own credential');
      final failures = logs.retrofitFailures.skip(failedFrom);
      expect(failures, hasLength(1));
      expect(
          failures.single,
          allOf(contains('could not be written'),
              contains('The enrollment $orphan it created was revoked')),
          reason: 'R1: the error names the enrollment and says it was revoked');
      expect(
          recordOf(await rosterAsPrimary(rootPredecessor), orphan!)['approval']
              ['state'],
          'revoked',
          reason: 'R1: the atServer holds the unsaved enrollment as revoked');
      await first.stop();

      final second = await openWith(rootPredecessor, settings, keys);

      final replacement = second.enrollmentId;
      expect(replacement, allOf(isNotNull, isNot('primary'), isNot(orphan)),
          reason: 'R1: the next start retrofits again, to a new enrollment');
      expect(
          recordOf(await rosterAsPrimary(rootPredecessor), replacement!)[
              'approval']['state'],
          'approved',
          reason: 'R1: the replacement is approved');
      expect(second.connection.current.isOnline, isTrue,
          reason: 'R1: the client authenticated as the replacement');
      expect(await authenticatedNoop(second), startsWith('data:'),
          reason: 'R1: its connection answers a verb that needs '
              'authentication');
      expect(
          (await settings.keysFor(rootPredecessor).read(rootPredecessor))
              .enrollmentToAuthenticateAs(),
          replacement,
          reason: 'R1: the keyfile names the replacement');
      expect(
          recordOf(
                  await rosterAsPrimary(rootPredecessor), 'primary')['approval']
              ['state'],
          'approved',
          reason: 'R1: a root predecessor keeps its life after its '
              'replacement\'s first login');
      await second.stop();
    }, timeout: Timeout(Duration(minutes: 6)));

    // State R2 hands to R3, R4a and R4b.
    String? scopedId;
    String? scopedReplacement;
    AtLookUp? predecessorSession;
    var predecessorLogins = 0;
    String? predecessorWroteBefore;
    final probeKey = 'r4probe.$scopedNamespace$scopedAtSign';

    final scopedKeyfile = testKeysFile(scopedAtSign, suffix: 'scoped_key');
    final scopedCopy = testKeysFile(scopedAtSign, suffix: 'scoped_copy_key');
    final masterKeyfile = testKeysFile(scopedAtSign, suffix: 'master_key');

    /// A connection that logs in as the scoped predecessor from the copy of
    /// its keyfile, calling [onLogin] at each login.
    AtLookUp predecessorLookUp(String store, {void Function()? onLogin}) {
      final copySettings =
          settingsFor(scopedAtSign, null, keyfile: scopedCopy, store: store);
      final asPredecessor = authenticatorFor(
          copySettings.keysFor(scopedAtSign), scopedAtSign,
          enrollmentId: scopedId);
      return copySettings.lookUps(
          atSign: scopedAtSign,
          rootDomain: AtRootDomain(rootDomain, virtualenvRootPort),
          authenticator: (executor) {
            onLogin?.call();
            return asPredecessor(executor);
          },
          secondaryAddressFinder: copySettings.secondaryAddressFinder);
    }

    /// The `enroll:request` a retrofit of the scoped predecessor sends.
    Future<String> retrofitRequest() async {
      final mldsa = await MlDsa65KeyPair.generate();
      return (EnrollVerbBuilder()
            ..appName = 'r2app'
            ..deviceName = 'r2device'
            ..apkamPublicKey = mldsa.atPublicKey.publicKey
            ..signingAlgo = 'mldsa65'
            ..namespaces = {scopedNamespace: 'rw'})
          .buildCommand();
    }

    Future<Map<String, String>> rosterAsMaster() async {
      await evictCachedAtClients();
      final master = await openOnline(
          scopedAtSign,
          settingsFor(scopedAtSign, null,
              keyfile: masterKeyfile, store: 'master'));
      final roster = {
        for (final e in await master.enrollments.list(statuses: [
          EnrollmentStatus.approved,
          EnrollmentStatus.revoked,
          EnrollmentStatus.pending,
        ]))
          e.enrollmentId!: e.status!
      };
      await master.stop();
      return roster;
    }

    test(
        'R2: a scoped predecessor reports the revoke it may not make, and the '
        'next start retrofits', () async {
      await activateThroughCli(
          scopedAtSign,
          auth_cli.EnrollerSettings(
              vePreference(cramSecret: at_demos.cramKeyMap[scopedAtSign]),
              atKeysFilePath: masterKeyfile,
              storagePath: 'storage/hive/$scopedAtSign/master'));
      AtClientManager.getInstance().reset();
      final operations = EnrollmentOperations(scopedAtSign);
      final otp = await operations.getOtp(masterKeyfile);
      final enrollSettings = settingsFor(scopedAtSign, null,
          keyfile: scopedKeyfile, store: 'enroll');
      final pending = await Atsign(scopedAtSign).enroll(
          otp: otp!,
          app: 'r2app',
          device: 'r2device',
          namespaces: {scopedNamespace: 'rw'},
          keys: enrollSettings.keysFor(scopedAtSign),
          preference: enrollSettings.preference,
          lookUps: enrollSettings.lookUps,
          secondaryAddressFinder: enrollSettings.secondaryAddressFinder,
          keyExchangeMode: EnrollmentKeyExchangeMode.legacy);
      final approved = pending.awaitApproval();
      await Future.delayed(const Duration(seconds: 5));
      scopedId = await operations.approve(
          atKeysFilePath: masterKeyfile,
          appName: 'r2app',
          deviceName: 'r2device');
      await approved;
      await evictCachedAtClients();
      expect(
          (await FileAtKeysIo(filePath: (_) => scopedKeyfile)
                  .read(scopedAtSign))
              .enrollmentToAuthenticateAs(),
          scopedId,
          reason: 'R2: the fixture is a keyfile naming the scoped enrollment');
      await File(scopedKeyfile).copy(scopedCopy);

      final settings = settingsFor(scopedAtSign, PqPosture.pqReady,
          keyfile: scopedKeyfile, store: 'scoped');
      final keys = _RefusesFirstRetrofitSave(settings.keysFor(scopedAtSign));
      final failedFrom = logs.retrofitFailures.length;
      final first = await openWith(scopedAtSign, settings, keys);

      final orphan = keys.refusedSaveNamed;
      expect(orphan, allOf(isNotNull, isNot(scopedId)),
          reason: 'R2: the save the keyfile refused names the enrollment the '
              'atServer approved');
      expect(keys.writes.take(2), ['update', 'flush refused'],
          reason: 'R2: the write check before the request took its write, '
              'and the refusal came from the save after approval');
      expect(first.enrollmentId, scopedId,
          reason: 'R2: a retrofit that did not complete leaves the client on '
              'the scoped enrollment');
      final failures = logs.retrofitFailures.skip(failedFrom);
      expect(failures, hasLength(1));
      expect(
          failures.single,
          allOf(
              contains('could not be written'),
              contains(
                  'The enrollment $orphan it created could NOT be revoked'),
              contains('__manage')),
          reason:
              'R2: the error says the revoke was refused, and why it can be');
      await first.stop();
      expect((await rosterAsMaster())[orphan], 'approved',
          reason: 'R2: the enrollment the scoped predecessor could not revoke '
              'is still approved');

      // NOTE: R4a's connection, authenticated as the predecessor before the
      // replacement's first login and kept open across it.
      predecessorSession =
          predecessorLookUp('r4a', onLogin: () => predecessorLogins++);
      expect(await predecessorSession!.pkamAuthenticate(), isTrue,
          reason: 'R4a: the fixture is a session authenticated as the '
              'predecessor');
      predecessorWroteBefore = await predecessorSession!
          .executeCommand('update:$probeKey before\n', auth: true);

      final second = await openWith(scopedAtSign, settings, keys);

      scopedReplacement = second.enrollmentId;
      expect(
          scopedReplacement, allOf(isNotNull, isNot(scopedId), isNot(orphan)),
          reason: 'R2: the next start retrofits again, to a new enrollment');
      expect(second.connection.current.isOnline, isTrue,
          reason: 'R2: the client authenticated as the replacement');
      expect(await authenticatedNoop(second), startsWith('data:'),
          reason: 'R2: its connection answers a verb that needs '
              'authentication');
      expect(
          (await settings.keysFor(scopedAtSign).read(scopedAtSign))
              .enrollmentToAuthenticateAs(),
          scopedReplacement,
          reason: 'R2: the keyfile names the replacement');
      await second.stop();
      expect((await rosterAsMaster())[scopedReplacement!], 'approved',
          reason: 'R2: the replacement is approved');
    }, timeout: Timeout(Duration(minutes: 6)));

    test(
        'R3: a copy of the scoped keyfile is refused at open once its '
        'replacement has logged in', () async {
      if (scopedId == null || scopedReplacement == null) {
        fail('R3 runs on what R2 left: R2 did not complete');
      }
      final settings = settingsFor(scopedAtSign, PqPosture.pqReady,
          keyfile: scopedCopy, store: 'copy');

      await expectLater(
          openWith(scopedAtSign, settings, settings.keysFor(scopedAtSign)),
          throwsA(isA<AtOpenRefusedException>().having((e) => '$e', 'message',
              allOf(contains('AT0027'), contains('is revoked')))),
          reason: 'R3: the replacement\'s first login revokes a scoped '
              'predecessor as superseded, so a copy of its keyfile is refused '
              'at open');
      expect((await rosterAsMaster())[scopedId!], 'revoked',
          reason: 'R3: the atServer holds the scoped predecessor as revoked');
    }, timeout: Timeout(Duration(minutes: 6)));

    test(
        'R4a: a session opened as the scoped predecessor is closed at its '
        'next command once the replacement has logged in', () async {
      if (predecessorSession == null || scopedId == null) {
        fail('R4a runs on the session R2 opened: R2 did not complete');
      }
      final session = predecessorSession!;
      expect(predecessorWroteBefore, startsWith('data:'),
          reason: 'R4a: before the replacement logged in, the session wrote to '
              'the predecessor\'s own namespace');
      final loginsBefore = predecessorLogins;

      await expectLater(
          session.executeCommand('llookup:$probeKey\n', auth: true),
          throwsA(isA<ConnectionInvalidException>()),
          reason: 'R4a: the active-enrollment check before every command '
              'closes a session whose enrollment was revoked, so its read '
              'gets no answer');
      expect(predecessorLogins, loginsBefore,
          reason: 'R4a: that read went on the session opened before the '
              'replacement logged in');
      await expectLater(
          session.executeCommand('update:$probeKey after\n', auth: true),
          throwsA(isA<UnAuthenticatedException>().having((e) => '$e', 'message',
              allOf(contains('AT0027'), contains('is revoked')))),
          reason: 'R4a: a new login as the revoked predecessor is refused '
              'with AT0027, so its write does not land');
      expect(predecessorLogins, loginsBefore + 1,
          reason: 'R4a: the write logged in afresh');
      await session.close();
    }, timeout: Timeout(Duration(minutes: 6)));

    test(
        'R4b: an un-revoked scoped predecessor cannot retrofit again once its '
        'replacement has logged in', () async {
      if (scopedId == null || scopedReplacement == null) {
        fail('R4b runs on what R2 left: R2 did not complete');
      }
      await evictCachedAtClients();
      final master = await openOnline(
          scopedAtSign,
          settingsFor(scopedAtSign, null,
              keyfile: masterKeyfile, store: 'master'));
      await master.enrollments.unrevoke(scopedId!);
      await master.stop();
      final rosterBefore = await rosterAsMaster();
      expect(rosterBefore[scopedId!], 'approved',
          reason: 'R4b: the fixture is the superseded predecessor approved '
              'again');

      final session = predecessorLookUp('r4b');
      expect(await session.pkamAuthenticate(), isTrue,
          reason: 'R4b: the un-revoked predecessor logs in');
      await expectLater(
          session.executeCommand(await retrofitRequest(), auth: true),
          throwsA(isA<AtLookUpException>().having((e) => '$e', 'message',
              allOf(contains('AT0009'), contains('already been replaced')))),
          reason: 'R4b: the guard refuses a second replacement once one has '
              'authenticated');
      await session.close();
      expect((await rosterAsMaster()).keys, unorderedEquals(rosterBefore.keys),
          reason: 'R4b: the refused request leaves no enrollment behind');
    }, timeout: Timeout(Duration(minutes: 6)));
  });
}

/// The real keyfile store, refusing the first save that would change which
/// enrollment the keyfile authenticates as: the save a retrofit makes once
/// the atServer has approved its request.
///
/// Everything else passes through, the retrofit's write check among it, which
/// is an `update` and is recorded in [writes] as one.
class _RefusesFirstRetrofitSave extends WrittenAtKeysIo {
  _RefusesFirstRetrofitSave(this._real);

  final FileAtKeysIo _real;
  bool _refused = false;

  /// Each write in order: `update`, `flush`, or `flush refused`.
  final List<String> writes = [];

  /// The enrollment the refused save would have named.
  String? refusedSaveNamed;

  @override
  Future<AtKeys> read(String atsign) => _real.read(atsign);

  @override
  Future write(String atsign, AtKeys atKeys) => _real.write(atsign, atKeys);

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) {
    writes.add('update');
    return _real.update(atsign, mutate);
  }

  @override
  Future<void> flush(Atsign atsign, AtKeys atKeys) async {
    final names = atKeys.enrollmentToAuthenticateAs();
    final onDisk =
        (await _real.read(atsign.toString())).enrollmentToAuthenticateAs();
    if (!_refused && names != onDisk) {
      _refused = true;
      refusedSaveNamed = names;
      writes.add('flush refused');
      throw FileSystemException('this keyfile refuses one save', 'keyfile');
    }
    writes.add('flush');
    await _real.flush(atsign, atKeys);
  }
}

/// Every log line, printed as usual and kept for a test to read.
class _CapturedLogs implements LoggingHandler {
  final List<String> lines = [];

  /// The client's report that a retrofit did not complete, in order.
  List<String> get retrofitFailures =>
      lines.where((line) => line.contains('did not complete')).toList();

  @override
  void call(Object record) {
    lines.add('$record');
    AtSignLogger.consoleLoggingHandler(record as dynamic);
  }
}
