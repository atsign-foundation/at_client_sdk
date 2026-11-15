import 'dart:convert';
import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'lifecycle_rig.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// The program at_activate and at_register name on each `from:` their clients
/// send to authenticate, with the preference `enrollerSettingsFrom` builds
/// from the command line.
///
/// Catalogue: features/at_client/from_names_program_and_sdk.feature
void main() {
  AtSignLogger.root_level = 'SHOUT';
  late Directory dir;
  final atClientCliVersion = _versionIn('pubspec.yaml');
  final atClientVersion = _versionIn('../at_client/pubspec.yaml');

  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  setUp(() => dir = Directory.systemTemp.createTempSync('from_names_'));

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
    dir.deleteSync(recursive: true);
  });

  /// What `enrollerSettingsFrom` makes of an onboard command line for
  /// [atSign] run as [program], with the client's store under the test's
  /// directory.
  Future<EnrollerSettings> settingsFrom(String atSign, String program,
      {String? cramSecret}) async {
    final keysPath = '${dir.path}/${atSign}_key.atKeys';
    final settings = enrollerSettingsFrom(
        AuthCliArgs().createOnboardCommandParser().parse([
          '-a', atSign, '-k', keysPath, //
          '-r', '127.0.0.1:${await refusedPort()}',
          '--posture', 'legacy',
          if (cramSecret != null) ...['-c', cramSecret],
        ]),
        program: program);
    return EnrollerSettings(settings.preference,
        atKeysFilePath: keysPath, storagePath: '${dir.path}/storage');
  }

  test('at_activate names itself and at_client', () async {
    const newborn = '@newborn';
    final activation = _activationServer();
    await activate(
        newborn,
        await settingsFrom(newborn, 'at_activate',
            cramSecret: 'the-one-time-secret'),
        atLookUp: activation);

    final enrolment =
        approvingAtServer(decide: (_) async => true, wrapped: []).lookUp;
    final client = await enrolDevice(
        atSign: approvingAtSign,
        settings: await settingsFrom(approvingAtSign, 'at_activate'),
        app: 'wavi',
        device: 'phone',
        otp: 'ABC123',
        namespaces: {'wavi': 'rw'},
        signingAlgo: SigningAlgoType.rsa2048,
        retryInterval: const Duration(milliseconds: 10),
        atLookUp: enrolment);
    await client.stop();

    final onboarding = await _configsInstalledOn(activation, newborn);
    expect(onboarding.length, greaterThanOrEqualTo(2),
        reason: 'the control: the CRAM login, then the PKAM one on the new '
            'keys');
    final enrolling = await _configsInstalledOn(enrolment, approvingAtSign);
    expect(enrolling, isNotEmpty,
        reason: 'the control: the approval handshake authenticated');
    for (final config in [...onboarding, ...enrolling]) {
      expect(config['appName'], 'at_activate');
      expect(config['appVersion'], atClientCliVersion);
      expect(config['sdkName'], 'atsign.dart.at_client');
      expect(config['sdkVersion'], atClientVersion);
    }
  });

  test(
      'Given at_register onboarding an atSign, when it authenticates with '
      'CRAM and then PKAM, then each from: names at_register', () async {
    const newborn = '@newborn';
    final activation = _activationServer();

    await activate(
        newborn,
        await settingsFrom(newborn, 'at_register',
            cramSecret: 'the-one-time-secret'),
        atLookUp: activation);

    final onboarding = await _configsInstalledOn(activation, newborn);
    expect(onboarding.length, greaterThanOrEqualTo(2),
        reason: 'the control: the CRAM login, then the PKAM one');
    for (final config in onboarding) {
      expect(config['appName'], 'at_register');
      expect(config['appVersion'], atClientCliVersion);
    }
  });
}

/// The version the pubspec at [path] declares.
String _versionIn(String path) => RegExp(r'^version:\s*(\S+)', multiLine: true)
    .firstMatch(File(path).readAsStringSync())!
    .group(1)!;

/// An atServer as the registrar leaves it: no encryption public key yet, an
/// enrollment approved as soon as it is asked for, and every update and
/// delete accepted.
MockAtLookupImpl _activationServer() {
  final lookUp = MockAtLookupImpl();
  when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
      .thenAnswer((i) async {
    final command = i.positionalArguments.first as String;
    if (command.startsWith('lookup:publickey')) return 'data:null';
    if (command.startsWith('enroll:')) {
      return 'data:${jsonEncode({
            'enrollmentId': 'first-1',
            'status': 'approved'
          })}';
    }
    throw StateError('the mocked atServer has no answer for: $command');
  });
  when(() => lookUp.executeVerb(any())).thenAnswer((i) async {
    final builder = i.positionalArguments.first as VerbBuilder;
    if (builder is UpdateVerbBuilder || builder is DeleteVerbBuilder) {
      return 'data:1';
    }
    throw StateError(
        'the mocked atServer has no answer for: ${builder.buildCommand()}');
  });
  when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async => true);
  when(() => lookUp.close()).thenAnswer((_) async {});
  when(lookUp.stop).thenAnswer((_) async {});
  when(() => lookUp.dropConnection()).thenAnswer((_) async {});
  when(() => lookUp.isConnectionAvailable()).thenReturn(false);
  return lookUp;
}

/// The clientConfig of the `from:` each authenticator installed on [lookUp]
/// sends for [atSign].
Future<List<Map<String, dynamic>>> _configsInstalledOn(
    MockAtLookupImpl lookUp, String atSign) async {
  final prefix = 'from:$atSign:clientConfig:';
  final configs = <Map<String, dynamic>>[];
  for (final authenticator in verify(() => lookUp.authenticator = captureAny())
      .captured
      .whereType<AtAuthenticator>()) {
    final recorder = _FromRecorder();
    await authenticator(recorder);
    expect(recorder.from, startsWith(prefix));
    configs.add(jsonDecode(recorder.from!.substring(prefix.length).trim())
        as Map<String, dynamic>);
  }
  return configs;
}

/// Keeps the `from:` an authenticator sends, answering it with nothing so the
/// authenticator stops there.
class _FromRecorder implements AtCommandExecutor {
  String? from;

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    from ??= command;
    return '';
  }
}
