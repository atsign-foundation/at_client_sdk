import 'dart:async';
import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart'
    show EnrollerSettings, cancelPending, enrolDevice;
import 'package:at_client_cli/src/util/keys_problem.dart'
    show keysProblemFooter;
import 'package:at_commons/at_builders.dart' show VerbBuilder;
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'keyfile_helpers.dart';
import 'lifecycle_rig.dart';

/// `at_activate cancel` gives up the pending enrollment request its keyfile
/// holds and sends nothing, and the programs that wait on such a request name
/// it. `at_activate enroll` refuses, as cancel does, a keyfile recorded for
/// another Atsign.
///
/// Catalogue: features/at_client_cli/cancel_pending_enrollment.feature
/// Catalogue: features/at_client_cli/enroll_adopts_pending_request.feature
///
/// at_activate runs in this process. The atDirectory its command lines name
/// is a loopback port that counts each connection made to it, so a command
/// that sends anything fails the test that says it sends nothing. The
/// atServer an enrollment request goes to is a mocked lookup answering by
/// verb. An approval another process files is filed here through a second
/// store on the same keyfile, which takes the keyfile's lock as a process
/// does.
void main() {
  const atSign = approvingAtSign;
  late Directory dir;
  late String keysPath;
  late ServerSocket atDirectory;
  var connections = 0;

  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('cancel_pending_');
    keysPath = '${dir.path}/keys/${atSign}_key.atKeys';
    connections = 0;
    atDirectory = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    atDirectory.listen((socket) {
      connections++;
      socket.destroy();
    });
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
    await atDirectory.close();
    dir.deleteSync(recursive: true);
  });

  /// at_activate run with [args]: its exit code and what it wrote to stdout
  /// and stderr, without colour or line redraws.
  Future<({int code, String out, String err})> atActivate(
      List<String> args) async {
    final out = _Captured();
    final err = _Captured();
    final code = await IOOverrides.runZoned(() => AtActivate.main(args),
        stdout: () => out, stderr: () => err);
    return (code: code, out: out.plain, err: err.plain);
  }

  /// at_activate cancel for [atSign] on the keyfile at [keysPath].
  Future<({int code, String out, String err})> cancel() => atActivate([
        'cancel', '-a', atSign, '-k', keysPath, //
        '-r', '127.0.0.1:${atDirectory.port}',
      ]);

  /// Files a request for [atSign] in the keyfile at [keysPath], or at [path],
  /// encrypted with [passPhrase] when one is given, as `at_activate enroll`
  /// run by app "buzz" on device "phone" does, against an atServer that has
  /// not decided it, and returns the symmetric key it wrapped for
  /// [approvingAtServer].
  Future<List<String>> fileRequest({String? path, String? passPhrase}) async {
    final keyfile =
        FileAtKeysIo(filePath: (_) => path ?? keysPath, passPhrase: passPhrase);
    final wrapped = <String>[];
    final undecided = approvingAtServer(
        decide: (_) async => throw AtAuthErrorReplyException(
            'Failed connecting to $atSign. error:AT0026:Apkam Auth Failed',
            errorCode: 'AT0026'),
        wrapped: wrapped);
    final rootPort = await refusedPort();
    await Atsign(atSign).enroll(
        otp: 'ABC123',
        app: 'buzz',
        device: 'phone',
        namespaces: {'buzz': 'rw'},
        keys: keyfile,
        preference: AtClientPreference()
          ..rootDomain = InternetAddress.loopbackIPv4.address
          ..rootPort = rootPort
          ..namespace = 'buzz',
        atLookUp: undecided.lookUp,
        lookUps: loopbackLookUps(),
        secondaryAddressFinder: CacheableSecondaryAddressFinder(
            InternetAddress.loopbackIPv4.address, rootPort));
    final filed = await keyfile.read(atSign);
    final info = filed.enrollmentInfo(approvedEnrollmentId);
    expect(filed.pendingEnrollmentIds, [approvedEnrollmentId],
        reason: 'the precondition: the keyfile holds the request');
    expect((info?.appName, info?.deviceName), ('buzz', 'phone'),
        reason: 'the precondition: buzz filed it on phone');
    return wrapped;
  }

  /// Files the approval of the request the keyfile at [keysPath] holds,
  /// through a store of its own on that keyfile, as another process waiting
  /// on the request does once the manager approves it; [wrapped] is the
  /// symmetric key the request wrapped.
  Future<void> approveFromAnotherStore(List<String> wrapped) async {
    final rootPort = await refusedPort();
    final approving =
        approvingAtServer(decide: (_) async => true, wrapped: wrapped);
    final waiting = await Atsign(atSign).resumeEnrollment(
        keys: FileAtKeysIo(filePath: (_) => keysPath),
        preference: AtClientPreference()
          ..rootDomain = InternetAddress.loopbackIPv4.address
          ..rootPort = rootPort,
        atLookUp: approving.lookUp,
        lookUps: loopbackLookUps(),
        secondaryAddressFinder: CacheableSecondaryAddressFinder(
            InternetAddress.loopbackIPv4.address, rootPort));
    await waiting!
        .awaitApproval(retryInterval: const Duration(milliseconds: 10));
  }

  /// Every file under [dir], by path, with its bytes.
  Map<String, List<int>> filesIn(Directory dir) => {
        for (final file in dir.listSync(recursive: true).whereType<File>())
          file.path: file.readAsBytesSync(),
      };

  test(
      'Given the atDirectory these tests count connections to, when an '
      'at_activate command that connects to it runs, then its connections '
      'are counted', () async {
    final run = await atActivate([
      'status', '-a', atSign, //
      '-r', '127.0.0.1:${atDirectory.port}',
    ]);

    expect(connections, greaterThan(0),
        reason: 'the control for "nothing is sent": at_activate status asks '
            'the atDirectory for $atSign, so the count rises; stderr: '
            '${run.err}');
  });

  test(
      "cancel removes the keyfile's pending request and says the manager can "
      'deny it', () async {
    await fileRequest();

    final run = await cancel();

    expect(await pendingIn(keysPath, atSign), isEmpty,
        reason: 'the keyfile holds no pending request');
    expect(connections, 0, reason: 'nothing is sent');
    expect(
        run.out,
        contains('Enrollment $approvedEnrollmentId of $atSign is cancelled, '
            'and its keys are removed from the AtKeys store ($keysPath).'),
        reason: 'it says the enrollment is cancelled, and where its keys '
            'were removed from');
    expect(
        run.out,
        contains('The request is still on the atServer: the manager of '
            '$atSign can deny it, or revoke it if they approved it already.'),
        reason: 'it says the manager can deny it, or revoke it');
    expect(run.code, 0, reason: 'it exits 0; stderr: ${run.err}');
  });

  test('enroll files a new request on a keyfile cancel emptied', () async {
    await fileRequest();
    expect((await cancel()).code, 0,
        reason: 'the precondition: cancel removed the request');
    expect(await pendingIn(keysPath, atSign), isEmpty,
        reason: 'the precondition: the keyfile holds no pending request');
    List<String>? filedWhileWaiting;
    final server = approvingAtServer(
        decide: (_) async {
          filedWhileWaiting ??= await pendingIn(keysPath, atSign);
          return true;
        },
        wrapped: []);
    final preference = AuthCliArgs.preferenceUnder(PqPosture.legacy)
      ..rootDomain = InternetAddress.loopbackIPv4.address
      ..rootPort = await refusedPort()
      ..namespace = 'at_activate';

    final client = await IOOverrides.runZoned(
        () => enrolDevice(
            atSign: atSign,
            settings: EnrollerSettings(preference,
                atKeysFilePath: keysPath, storagePath: '${dir.path}/storage'),
            app: 'buzz',
            device: 'phone',
            otp: 'ABC123',
            namespaces: {'buzz': 'rw'},
            signingAlgo: SigningAlgoType.rsa2048,
            retryInterval: const Duration(milliseconds: 10),
            atLookUp: server.lookUp),
        stdout: () => _Captured(),
        stderr: () => _Captured());

    expect(server.sent.where((c) => c.startsWith('enroll:')), hasLength(1),
        reason: 'it submits a new enrollment request');
    expect(filedWhileWaiting, [approvedEnrollmentId],
        reason: 'it files the new request in that keyfile, where its wait '
            'for approval finds it');
    await client.stop();
  });

  test('cancel refuses a keyfile holding live keys', () async {
    const refusal = 'holds live keys for $atSign, which at_activate cancel '
        'never removes, so nothing is changed. The manager of $atSign can '
        "revoke this device's enrollment.";

    await FileAtKeysIo(filePath: (_) => keysPath)
        .write(atSign, randomLegacyKeys());
    final before = filesIn(dir);

    final run = await cancel();

    expect(filesIn(dir), before,
        reason: 'given live keys before it runs: the keyfile is unchanged');
    expect(run.err, contains('The AtKeys store ($keysPath) $refusal'),
        reason: 'given live keys before it runs: it says the keyfile holds '
            'live keys, which cancel never removes, and that the manager can '
            'revoke');
    expect(run.code, 1, reason: 'given live keys before it runs: it exits 1');

    File(keysPath).deleteSync();
    final wrapped = await fileRequest();
    List<int>? approved;
    final err = _Captured();

    final code = await IOOverrides.runZoned(
        () => cancelPending(
            atSign: atSign,
            settings: _ApprovalFiledFirst(keysPath, () async {
              await approveFromAnotherStore(wrapped);
              approved = File(keysPath).readAsBytesSync();
            })),
        stderr: () => err);

    expect(approved, isNotNull,
        reason: 'the control: the approval was filed after cancel first '
            'read the keyfile, before cancel took its lock');
    expect(File(keysPath).readAsBytesSync(), approved,
        reason: 'given live keys filed as it cancels: the keyfile is '
            'unchanged by cancel');
    expect(err.plain, contains('The AtKeys store ($keysPath) $refusal'),
        reason: 'given live keys filed as it cancels: it says the keyfile '
            'holds live keys, not that the request is cancelled');
    expect(code, 1, reason: 'given live keys filed as it cancels: it exits 1');
  });

  for (final (keyfile, given) in <(String, Future<void> Function())>[
    (
      'a keyfile holding no request and no keys',
      () => FileAtKeysIo(filePath: (_) => keysPath).write(atSign, AtKeys()),
    ),
    ('no keyfile at the path given', () async {}),
  ]) {
    test('cancel says when there is nothing to cancel', () async {
      await given();
      final before = filesIn(dir);

      final run = await cancel();

      expect(filesIn(dir), before, reason: 'given $keyfile: nothing changes');
      expect(connections, 0, reason: 'given $keyfile: nothing is sent');
      expect(
          run.err,
          contains('$atSign has no pending enrollment request in the AtKeys '
              'store ($keysPath), so there is nothing to cancel.'),
          reason: 'given $keyfile');
      expect(run.code, 1, reason: 'given $keyfile');
    });
  }

  test(
      'Given no --posture, when at_activate cancel runs, then it prints no '
      'notice of a posture', () async {
    final notice = AuthCliArgs.postureForEnroller(
        AuthCliArgs().createCancelCommandParser().parse([])).notice;
    expect(notice, isNotNull,
        reason: 'the control: with no --posture, an enroller has a notice to '
            'print');

    final run = await cancel();

    expect(run.err, contains('so there is nothing to cancel'),
        reason: 'the control: cancel ran, and what it wrote to stderr is '
            'captured');
    expect('${run.out}${run.err}', isNot(contains(notice!)),
        reason: 'no posture changes what cancel does, so it says nothing '
            'about one');
  });

  for (final (keyfile, given, report)
      in <(String, Future<void> Function(), List<Matcher> Function())>[
    (
      'a keyfile that is not valid JSON',
      () async => File(keysPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('{"not json'),
      () => [
            startsWith('The keys for $atSign in the AtKeys store ($keysPath) '
                'could not be read: it is not valid JSON'),
            equals(keysProblemFooter),
          ],
    ),
    (
      'a keyfile that has a passphrase when no -P is given',
      () => fileRequest(passPhrase: 'a passphrase'),
      () => [
            equals('Could not read the keys for $atSign at $keysPath: the '
                'passphrase is wrong or missing.'),
            equals('  If the keyfile has a passphrase, pass it with -P.'),
            equals(keysProblemFooter),
          ],
    ),
  ]) {
    test(
        'cancel reports a keyfile it cannot read as at_activate reports keys '
        'problems', () async {
      await given();
      final before = filesIn(dir);

      final run = await cancel();

      expect(filesIn(dir), before, reason: 'given $keyfile: nothing changes');
      expect(connections, 0, reason: 'given $keyfile: nothing is sent');
      expect(run.err.split('\n'), containsAllInOrder(report()),
          reason: "given $keyfile: at_activate's report for that keyfile, "
              'ending with its footer');
      expect(run.err, isNot(contains('contact support@atsign.com')),
          reason: 'given $keyfile: not the generic error');
      expect(run.code, 1, reason: 'given $keyfile: it exits 1');
    });
  }

  test('cancel refuses a keyfile recorded for another Atsign', () async {
    await fileRequest();
    final before = filesIn(dir);

    final run = await atActivate([
      'cancel', '-a', '@bob', '-k', keysPath, //
      '-r', '127.0.0.1:${atDirectory.port}',
    ]);

    expect(filesIn(dir), before, reason: 'nothing changes');
    expect(connections, 0, reason: 'nothing is sent');
    expect(
        run.err,
        contains('The keys in the AtKeys store ($keysPath) are for $atSign, '
            'not @bob. Check -a and -k.'),
        reason: 'it says the keys are for $atSign, not @bob, and to check -a '
            'and -k');
    expect(run.code, 1, reason: 'it exits 1');
  });

  test('enroll refuses a keyfile recorded for another Atsign', () async {
    await fileRequest();
    final before = filesIn(dir);

    final run = await atActivate([
      'enroll', '-a', '@bob', '-k', keysPath, //
      '--app', 'buzz', '--device', 'phone', '--namespaces', 'buzz:rw',
      '--passcode', 'ABC123',
      '-r', '127.0.0.1:${atDirectory.port}',
    ]).timeout(const Duration(seconds: 10),
        onTimeout: () => fail('it resumes nothing, so it has nothing to wait '
            'on: enroll was still running after 10 seconds'));

    expect(filesIn(dir), before, reason: 'nothing changes');
    expect(run.err, isNot(contains('Resuming enrollment')),
        reason: 'it resumes nothing');
    expect(connections, 0, reason: 'it sends nothing');
    expect(
        run.err,
        contains('The keys in the AtKeys store ($keysPath) are for $atSign, '
            'not @bob. Check -a and -k.'),
        reason: 'it says the keys are for $atSign, not @bob, and to check -a '
            'and -k');
    expect(run.code, 1, reason: 'it exits 1');
  });

  test('cancel needs the keyfile, as enroll does', () async {
    final run = await atActivate([
      'cancel', '-a', atSign, //
      '-r', '127.0.0.1:${atDirectory.port}',
    ]);

    expect(
        run.err,
        contains('Argument error for command cancel: The -k option is '
            'mandatory for the "cancel" command'),
        reason: 'it says -k is mandatory for cancel');
    expect(run.code, 1, reason: 'it exits 1');
  });

  test(
      'a CLIBase program waiting on a pending request names at_activate '
      'cancel', () async {
    final wrapped = await fileRequest();
    final server =
        approvingAtServer(decide: (_) async => true, wrapped: wrapped);
    when(() => server.lookUp.stopNotifications()).thenAnswer((_) async {});
    final err = _Captured();

    final cli = await IOOverrides.runZoned(
        () => CLIBase.fromCommandLineArgs([
              '-a', atSign, //
              '-k', keysPath,
              '-s', '${dir.path}/storage',
              '-r', '127.0.0.1:${atDirectory.port}',
              '--max-connect-attempts', '1',
              '--never-sync',
            ],
                parser: CLIBase.createArgsParser(namespace: 'buzz'),
                lookUps: (
                        {required String atSign,
                        required AtRootDomain rootDomain,
                        required AtAuthenticator? authenticator,
                        SecondaryAddressFinder? secondaryAddressFinder}) =>
                    server.lookUp,
                approvalRetryInterval: const Duration(milliseconds: 10)),
        stderr: () => err);

    expect(
        err.plain.split('\n'),
        containsAllInOrder([
          'Waiting for approval of enrollment $approvedEnrollmentId of '
              '$atSign',
          'To give the request up instead, stop this program and run '
              'at_activate cancel -a $atSign -k $keysPath',
        ]),
        reason: 'it says it is waiting, then that at_activate cancel with its '
            'keyfile gives the request up');
    await cli.atClient.stop();
  });

  test('the at_activate cancel command a wait names works as printed',
      () async {
    const passPhrase = 'a secret phrase';
    final spaced = '${dir.path}/my keys/${atSign}_key.atKeys';
    final wrapped = await fileRequest(path: spaced, passPhrase: passPhrase);
    await expectLater(FileAtKeysIo(filePath: (_) => spaced).read(atSign),
        throwsA(isA<AtKeysPassphraseException>()),
        reason: 'the control: the keyfile has a passphrase');
    final command = "at_activate cancel -a $atSign -k '$spaced' "
        '-P <passphrase>';

    final report = await atActivate([
      'otp', '-a', atSign, '-k', spaced, '-P', passPhrase, //
      '-r', '127.0.0.1:${atDirectory.port}',
    ]);

    expect(
        report.err.split('\n'), contains('  To give it up instead: $command'),
        reason: "the command at_activate's report names quotes the path and "
            'carries -P <passphrase>; stderr: ${report.err}');
    expect('${report.out}${report.err}', isNot(contains(passPhrase)),
        reason: "at_activate's report never prints the passphrase itself");

    final server =
        approvingAtServer(decide: (_) async => true, wrapped: wrapped);
    when(() => server.lookUp.stopNotifications()).thenAnswer((_) async {});
    final out = _Captured();
    final err = _Captured();
    final cli = await IOOverrides.runZoned(
        () => CLIBase.fromCommandLineArgs([
              '-a', atSign, //
              '-k', spaced,
              '-P', passPhrase,
              '-s', '${dir.path}/storage',
              '-r', '127.0.0.1:${atDirectory.port}',
              '--max-connect-attempts', '1',
              '--never-sync',
            ],
                parser: CLIBase.createArgsParser(namespace: 'buzz'),
                lookUps: (
                        {required String atSign,
                        required AtRootDomain rootDomain,
                        required AtAuthenticator? authenticator,
                        SecondaryAddressFinder? secondaryAddressFinder}) =>
                    server.lookUp,
                approvalRetryInterval: const Duration(milliseconds: 10)),
        stdout: () => out,
        stderr: () => err);

    expect(
        err.plain.split('\n'),
        contains('To give the request up instead, stop this program and run '
            '$command'),
        reason: 'the command CLIBase names quotes the path and carries -P '
            '<passphrase>; stderr: ${err.plain}');
    expect('${out.plain}${err.plain}', isNot(contains(passPhrase)),
        reason: 'CLIBase never prints the passphrase itself');
    await cli.atClient.stop();
  },
      skip: Platform.isWindows
          ? 'the path is quoted as a POSIX shell takes it'
          : false);

  test(
      "at_activate's report of a keyfile waiting on a request names "
      'at_activate cancel', () async {
    await fileRequest();

    final run = await atActivate([
      'otp', '-a', atSign, '-k', keysPath, //
      '-r', '127.0.0.1:${atDirectory.port}',
    ]);

    expect(
        run.err.split('\n'),
        containsAllInOrder([
          'The keyfile at $keysPath holds only a pending enrollment request '
              'for $atSign (id $approvedEnrollmentId). Once it is approved, '
              'run the same at_activate enroll command again to finish it.',
          '  To give it up instead: at_activate cancel -a $atSign -k '
              '$keysPath',
        ]),
        reason: 'the report says to run enroll again once the request is '
            'approved, or at_activate cancel to give it up');
    expect(run.code, 1, reason: 'it exits 1');
  });
}

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// Settings for the keyfile at a path, whose store is an [_ApprovedFirst].
class _ApprovalFiledFirst extends EnrollerSettings {
  _ApprovalFiledFirst(String path, this.approve)
      : super(
            AtClientPreference()
              ..rootDomain = '127.0.0.1'
              ..rootPort = 1,
            atKeysFilePath: path);

  final Future<void> Function() approve;

  @override
  FileAtKeysIo keysFor(String atSign) =>
      _ApprovedFirst(atKeysFilePath, approve);
}

/// The store on the keyfile at a path, whose first [update] waits for
/// [approve] to file the approval of the request the keyfile holds before it
/// takes the keyfile's lock.
class _ApprovedFirst extends FileAtKeysIo {
  _ApprovedFirst(String path, this.approve) : super(filePath: (_) => path);

  final Future<void> Function() approve;
  bool _approved = false;

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    if (!_approved) {
      _approved = true;
      await approve();
    }
    return super.update(atsign, mutate);
  }
}

/// Stands in for stdout or stderr, keeping what is written to it.
class _Captured implements Stdout {
  final List<String> written = [];

  /// What was written, without colour codes or line redraws.
  String get plain => written
      .join()
      .replaceAll(RegExp(r'\x1b\[[0-9;]*[A-Za-z]'), '')
      .replaceAll('\r', '\n');

  @override
  void write(Object? object) => written.add('$object');

  @override
  void writeln([Object? object = '']) => written.add('$object\n');

  @override
  bool get hasTerminal => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
