import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart'
    show EnrollerSettings, enrolDevice;
import 'package:at_commons/at_builders.dart' show VerbBuilder;
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'keyfile_helpers.dart';
import 'lifecycle_rig.dart';

/// `at_activate cancel` gives up the pending enrollment request its keyfile
/// holds and sends nothing, and the programs that wait on such a request name
/// it.
///
/// Catalogue: features/at_client_cli/cancel_pending_enrollment.feature
///
/// at_activate runs in this process. The atDirectory its command lines name
/// is a loopback port that counts each connection made to it, so a command
/// that sends anything fails the test that says it sends nothing. The
/// atServer an enrollment request goes to is a mocked lookup answering by
/// verb.
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

  /// Files a request for [atSign] in the keyfile at [keysPath], as
  /// `at_activate enroll` run by app "buzz" on device "phone" does, against
  /// an atServer that has not decided it, and returns the symmetric key it
  /// wrapped for [approvingAtServer].
  Future<List<String>> fileRequest() async {
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
        keys: FileAtKeysIo(filePath: (_) => keysPath),
        preference: AtClientPreference()
          ..rootDomain = InternetAddress.loopbackIPv4.address
          ..rootPort = rootPort
          ..namespace = 'buzz',
        atLookUp: undecided.lookUp,
        lookUps: loopbackLookUps(),
        secondaryAddressFinder: CacheableSecondaryAddressFinder(
            InternetAddress.loopbackIPv4.address, rootPort));
    final info = (await FileAtKeysIo(filePath: (_) => keysPath).read(atSign))
        .enrollmentInfo(approvedEnrollmentId);
    expect(await pendingIn(keysPath, atSign), [approvedEnrollmentId],
        reason: 'the precondition: the keyfile holds the request');
    expect((info?.appName, info?.deviceName), ('buzz', 'phone'),
        reason: 'the precondition: buzz filed it on phone');
    return wrapped;
  }

  /// Every file under [dir], by path, with its bytes.
  Map<String, List<int>> filesIn(Directory dir) => {
        for (final file in dir.listSync(recursive: true).whereType<File>())
          file.path: file.readAsBytesSync(),
      };

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
            'and its keys are removed from the AtKeys store ($keysPath).'));
    expect(
        run.out,
        contains('The request is still on the atServer: the manager of '
            '$atSign can deny it, or revoke it if they approved it already.'));
    expect(run.code, 0, reason: 'stderr: ${run.err}');
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
    await FileAtKeysIo(filePath: (_) => keysPath)
        .write(atSign, randomLegacyKeys());
    final before = filesIn(dir);

    final run = await cancel();

    expect(filesIn(dir), before, reason: 'the keyfile is unchanged');
    expect(
        run.err,
        contains('The AtKeys store ($keysPath) holds live keys for $atSign, '
            'which at_activate cancel never removes, so nothing is changed. '
            "The manager of $atSign can revoke this device's enrollment."));
    expect(run.code, 1);
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

  test('cancel needs the keyfile, as enroll does', () async {
    final run = await atActivate([
      'cancel', '-a', atSign, //
      '-r', '127.0.0.1:${atDirectory.port}',
    ]);

    expect(
        run.err,
        contains('Argument error for command cancel: The -k option is '
            'mandatory for the "cancel" command'));
    expect(run.code, 1);
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
        ]));
    await cli.atClient.stop();
  });

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
        ]));
    expect(run.code, 1);
  });
}

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

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
