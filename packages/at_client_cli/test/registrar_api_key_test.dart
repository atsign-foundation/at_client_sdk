import 'dart:convert';
import 'dart:io';

import 'package:at_client_cli/src/register/onboarding_util.dart';
import 'package:at_client_cli/src/register/register.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger, LoggingHandler;
import 'package:test/test.dart';

import 'fixtures/loopback_registrar.dart';

class _RecordedLogs implements LoggingHandler {
  final List<String> messages = [];

  @override
  void call(dynamic record) => messages.add('${record.message}');
}

/// Where at_register and at_activate take the registrar API key from,
/// observed against a registrar on the loopback interface, so nothing
/// reaches my.atsign.com.
///
/// Catalogue: features/at_client_cli/registrar_api_key.feature
void main() {
  const key = 'app-key-3f9c71';
  const pointer = 'via the registrar at my.atsign.com';
  late Directory home;

  setUp(() =>
      home = Directory.systemTemp.createTempSync('registrar_api_key_test_'));
  tearDown(() => home.deleteSync(recursive: true));

  /// [fixture] run with [args], [home] as its home directory and [input] on
  /// its stdin. `AT_REGISTRAR_API_KEY` is [registrarApiKey], or unset when
  /// that is null, whatever this process's environment holds.
  Future<({int exitCode, String output})> runFixture(
      String fixture, List<String> args,
      {String? registrarApiKey, String input = ''}) async {
    final environment = Map.of(Platform.environment)
      ..remove('AT_REGISTRAR_API_KEY')
      ..['HOME'] = home.path;
    if (registrarApiKey != null) {
      environment['AT_REGISTRAR_API_KEY'] = registrarApiKey;
    }
    final process = await Process.start(
        Platform.resolvedExecutable, ['test/fixtures/$fixture', ...args],
        environment: environment, includeParentEnvironment: false);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(input);
    await process.stdin.close();
    final exitCode = await process.exitCode.timeout(const Duration(seconds: 90),
        onTimeout: () {
      process.kill();
      return -1;
    });
    return (exitCode: exitCode, output: '${await stdout}${await stderr}');
  }

  /// at_register for an atSign whose keyfile is already there, so the
  /// activation after registration fails before it reaches an atServer.
  Future<({int exitCode, String output})> atRegister(
      {String? registrarApiKey}) {
    File('${home.path}/.atsign/keys/@registered_key.atKeys')
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
    return runFixture('at_register_against_loopback.dart', ['hands-over-cram'],
        registrarApiKey: registrarApiKey, input: 'ABCD\n' * 4);
  }

  test(
      'at_register with no registrar API key refuses before it reaches the '
      'registrar', () async {
    final control = await atRegister(registrarApiKey: key);
    expect(
        control.output,
        contains('registrar served GET /api/app/v3/get-free-atsign '
            'with the key set'),
        reason: 'the control: with a key set, the registrar is reached');

    final run = await atRegister();

    expect(run.output, contains(pointer));
    expect(run.output, contains('AT_REGISTRAR_API_KEY'));
    expect(run.output, isNot(contains('registrar served')),
        reason: 'nothing is sent to the registrar');
    expect(run.exitCode, 8);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
      'at_register with a registrar API key that is set but empty refuses as '
      'with none', () async {
    final run = await atRegister(registrarApiKey: '');

    expect(run.output, contains(pointer));
    expect(run.output, isNot(contains('registrar served')),
        reason: 'nothing is sent to the registrar');
    expect(run.exitCode, 8);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('A registrar API key that is empty or blank is refused as a missing one',
      () {
    for (final blank in ['', ' ', '\t\n']) {
      expect(
          () => OnboardingUtil(blank),
          throwsA(isA<Exception>()
              .having((e) => '$e', 'message', contains(noRegistrarApiKey))),
          reason: 'a key of ${jsonEncode(blank)} names no app');
    }
  });

  test(
      'at_activate onboard without a CRAM secret and with no registrar API '
      'key refuses the same way', () async {
    const args = ['onboard', '-a', '@alice', '-y', '--debug'];
    final control = await runFixture('at_activate_against_loopback.dart', args,
        registrarApiKey: key);
    expect(
        control.output,
        contains('registrar served POST /api/app/v3/authenticate/atsign '
            'with the key set'),
        reason: 'the control: with a key set, the registrar is reached');
    expect(control.output, contains('Sending request to url'),
        reason: 'the control: --debug logs the registrar request');
    expect(control.output, isNot(contains(key)),
        reason: 'no log line carries the registrar API key');

    final run = await runFixture('at_activate_against_loopback.dart', args);

    expect(run.output, contains(pointer));
    expect(run.output, contains('AT_REGISTRAR_API_KEY'));
    expect(run.output, isNot(contains('registrar served')),
        reason: 'nothing is sent to the registrar');
    expect(run.exitCode, isNot(0));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('A registrar API key that is set is the one sent', () async {
    final run = await atRegister(registrarApiKey: key);
    final served = RegExp(r'registrar served .*').allMatches(run.output);
    expect(served, isNotEmpty,
        reason: 'the premise: at_register asked the registrar');
    expect(served.map((m) => m[0]), everyElement(endsWith('with the key set')),
        reason: 'every request carries the key set as its Authorization '
            'header');
    expect(run.output, isNot(contains(key)));

    // Logging at its finest, as at_register's own steps run it.
    final registrar = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => registrar.close(force: true));
    final authorizations = <String?>[];
    registrar.listen((request) async {
      await utf8.decoder.bind(request).join();
      authorizations
          .add(request.headers.value(HttpHeaders.authorizationHeader));
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(request.uri.path == '/api/app/v3/get-free-atsign'
            ? {
                'data': {'atsign': 'registered'}
              }
            : {'message': 'Sent Successfully'}));
      await request.response.close();
    });
    final recorded = _RecordedLogs();
    final level = AtSignLogger.root_level;
    final handler = AtSignLogger.defaultLoggingHandler;
    AtSignLogger.root_level = 'finest';
    AtSignLogger.defaultLoggingHandler = recorded;
    addTearDown(() {
      AtSignLogger.root_level = level;
      AtSignLogger.defaultLoggingHandler = handler;
    });

    await HttpOverrides.runWithHttpOverrides(
        () => RegistrationFlow(
                {'email': 'probe@example.com', 'authority': 'my.atsign.com'},
                OnboardingUtil(key))
            .add(GetFreeAtsign())
            .add(RegisterAtsign())
            .start(),
        ToLoopbackRegistrar(registrar.port));

    expect(authorizations, [key, key]);
    expect(recorded.messages, contains(contains('Current Task')),
        reason: 'the control: the flow logged its steps at finest');
    expect(recorded.messages, contains(contains('Sending request to url')),
        reason: 'the control: the request was logged at finest');
    expect(recorded.messages.where((m) => m.contains(key)), isEmpty,
        reason: 'no log line carries the registrar API key');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
