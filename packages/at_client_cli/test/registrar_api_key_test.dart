import 'dart:convert';
import 'dart:io';

import 'package:at_client_cli/src/register/onboarding_util.dart';
import 'package:at_client_cli/src/register/registrar_api_constants.dart';
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

  /// Every request the loopback registrar served in [output], as it logged it.
  List<String> servedIn(String output) => [
        for (final m in RegExp(r'registrar served .*').allMatches(output)) m[0]!
      ];

  /// Whether [output] carries the built-in registrar API key, asked as a
  /// boolean so that a failure never prints it.
  bool carriesBuiltInKey(String output) =>
      output.contains(RegistrarApiConstants.authorization);

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

  test('at_register with no registrar API key sends the built-in key',
      () async {
    final run = await atRegister();

    expect(carriesBuiltInKey(run.output), isFalse,
        reason: 'the built-in key is never echoed');
    final served = servedIn(run.output);
    expect(served, isNotEmpty,
        reason: 'the premise: at_register asked the registrar');
    expect(served, everyElement(endsWith('with the built-in key')));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
      'at_register with a registrar API key that is set but empty sends the '
      'built-in key, as with none', () async {
    final run = await atRegister(registrarApiKey: '');

    expect(carriesBuiltInKey(run.output), isFalse,
        reason: 'the built-in key is never echoed');
    final served = servedIn(run.output);
    expect(served, isNotEmpty,
        reason: 'the premise: at_register asked the registrar');
    expect(served, everyElement(endsWith('with the built-in key')));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
      'A registrar API key holding a character an HTTP header cannot carry is '
      'refused without being quoted', () {
    for (final bad in ['$key\n', '$key\r', '$keyé']) {
      expect(
          () => OnboardingUtil(bad),
          throwsA(isA<Exception>()
              .having((e) => '$e', 'message', contains(badRegistrarApiKey))
              .having((e) => '$e', 'message', isNot(contains(key)))),
          reason: 'refused: ${jsonEncode(bad.substring(key.length))}');
    }
  });

  test(
      'at_register with a registrar API key a header cannot carry refuses '
      'before it reaches the registrar, and never echoes the key', () async {
    final run = await atRegister(registrarApiKey: '$key\n');

    expect(carriesBuiltInKey(run.output), isFalse,
        reason: 'the built-in key is never echoed');
    expect(run.output, contains(badRegistrarApiKey));
    expect(run.output, isNot(contains(key)));
    expect(run.output, isNot(contains('registrar served')),
        reason: 'nothing is sent to the registrar');
    expect(run.exitCode, 8, reason: 'at_register refuses the key with 8');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
      'A registrar API key that is absent, empty or blank is replaced by the '
      'built-in one', () {
    for (final blank in [null, '', ' ', '\t\n']) {
      expect(
          OnboardingUtil(blank).registrarApiKey ==
              RegistrarApiConstants.authorization,
          isTrue,
          reason: 'a key of ${jsonEncode(blank)} names no app');
    }
    expect(OnboardingUtil(key).registrarApiKey == key, isTrue,
        reason: 'the control: a key that is set is the one used');
  });

  test(
      'at_activate onboard without a CRAM secret and with no registrar API '
      'key sends the built-in key', () async {
    const args = ['onboard', '-a', '@alice', '-y', '--debug'];
    final run = await runFixture('at_activate_against_loopback.dart', args);

    expect(carriesBuiltInKey(run.output), isFalse,
        reason: 'no log line carries the built-in key');
    expect(
        run.output,
        contains('registrar served POST /api/app/v3/authenticate/atsign '
            'with the built-in key'));
    expect(run.output, contains('Sending request to url'),
        reason: 'the control: --debug logs the registrar request');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
      'at_activate onboard with a registrar API key set sends that key, not '
      'the built-in one', () async {
    const args = ['onboard', '-a', '@alice', '-y', '--debug'];
    final run = await runFixture('at_activate_against_loopback.dart', args,
        registrarApiKey: key);

    expect(carriesBuiltInKey(run.output), isFalse,
        reason: 'the built-in key is never echoed');
    expect(
        run.output,
        contains('registrar served POST /api/app/v3/authenticate/atsign '
            'with the key set'));
    expect(run.output, contains('Sending request to url'),
        reason: 'the control: --debug logs the registrar request');
    expect(run.output, isNot(contains(key)),
        reason: 'no log line carries the registrar API key');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
      'at_activate onboard without a CRAM secret and with a registrar API key '
      'a header cannot carry refuses before it shows the backup prompt',
      () async {
    const prompt = 'IMPORTANT - READ CAREFULLY';
    const args = ['onboard', '-a', '@alice'];
    final control = await runFixture('at_activate_against_loopback.dart', args,
        registrarApiKey: key, input: 'N\n');
    expect(carriesBuiltInKey(control.output), isFalse);
    expect(control.output, contains(prompt),
        reason: 'the control: with a usable key set, the prompt is shown');
    expect(control.exitCode, 0);

    final run = await runFixture('at_activate_against_loopback.dart', args,
        registrarApiKey: '$key\n', input: 'Y\n');

    expect(carriesBuiltInKey(run.output), isFalse,
        reason: 'the built-in key is never echoed');
    expect(run.output, contains(badRegistrarApiKey));
    expect(run.output, isNot(contains(prompt)));
    expect(run.output, isNot(contains(key)));
    expect(run.output, isNot(contains('registrar served')),
        reason: 'nothing is sent to the registrar');
    expect(run.exitCode, 1, reason: 'at_activate fails with 1');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('A registrar API key that is set is the one sent', () async {
    final run = await atRegister(registrarApiKey: key);
    expect(carriesBuiltInKey(run.output), isFalse,
        reason: 'the built-in key is never echoed');
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

    expect(authorizations, hasLength(2));
    expect(authorizations.every((sent) => sent == key), isTrue,
        reason: 'every request carries the key set, not the built-in one');
    expect(recorded.messages.any((m) => carriesBuiltInKey(m)), isFalse);
    expect(recorded.messages, contains(contains('Current Task')),
        reason: 'the control: the flow logged its steps at finest');
    expect(recorded.messages, contains(contains('Sending request to url')),
        reason: 'the control: the request was logged at finest');
    expect(recorded.messages.where((m) => m.contains(key)), isEmpty,
        reason: 'no log line carries the registrar API key');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
