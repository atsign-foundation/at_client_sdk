import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:test/test.dart';

import 'test_utils/fake_at_server.dart';
import 'test_utils/from_recorder.dart';
import 'test_utils/ml_dsa_keyfile.dart';
import 'test_utils/recorded_logs.dart';
import 'test_utils/test_keypairs.dart';

/// Catalogue: features/at_client/from_names_program_and_sdk.feature
void main() {
  const atSign = '@alice';
  const prefix = 'from:$atSign:clientConfig:';
  final atClientVersion = pubspecVersion();
  final keys = keysHoldingApkam(atSign, null, pkamKeyPairFor(atSign, null));

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  /// The clientConfig every one of [froms] carries, which must be the same;
  /// [froms] must not be empty.
  Map<String, dynamic> configOf(List<String> froms) {
    expect(froms, isNotEmpty,
        reason: 'the control: the connection authenticated at this atServer');
    expect(froms, everyElement(startsWith(prefix)),
        reason: 'an authenticating from: without a clientConfig');
    final configs = {
      for (final from in froms) from.substring(prefix.length).trim()
    };
    expect(configs, hasLength(1),
        reason: 'one connection sends one config every time it logs in');
    return jsonDecode(configs.single) as Map<String, dynamic>;
  }

  void expectNamesAcmeChatAndAtClient(Map<String, dynamic> config) {
    expect(config['appName'], 'acme_chat');
    expect(config['appVersion'], '2.3.1');
    expect(config['sdkName'], 'atsign.dart.at_client');
    expect(config['sdkVersion'], atClientVersion,
        reason: 'at_client names its own version, the one its pubspec '
            'declares');
  }

  /// A client for [atSign] whose particulars name [appName] at [appVersion]
  /// on [platform], opened over a fake atServer that runs the client's own
  /// authenticator.
  Future<(AtClient, FakeAtServer)> openClient(
      {String? appName = 'acme_chat',
      String? appVersion = '2.3.1',
      String? platform,
      String rootDomain = '127.0.0.1'}) async {
    final server = FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
    final client = await Atsign(atSign).open(
        keys: keys,
        preference: AtClientPreference()
          ..namespace = 'wavi'
          ..rootDomain = rootDomain
          ..atClientParticulars.appName = appName
          ..atClientParticulars.appVersion = appVersion
          ..atClientParticulars.platform = platform,
        storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
        lookUps: server.lookUps,
        secondaryAddressFinder: server.addressFinder);
    return (client, server);
  }

  AtLookUp verbLookUp(AtClient client) => client.getRemoteSecondary()!.atLookUp;

  AtLookUp monitorLookUp(AtClient client) =>
      (client.notificationService as NotificationServiceImpl).monitor.lookUp;

  /// Runs [program] in an isolate of its own and answers what it sends back.
  Future<Map<Object?, Object?>> runProgram(Uri program) async {
    final results = ReceivePort();
    final errors = ReceivePort();
    await Isolate.spawnUri(program, const [], results.sendPort,
        onError: errors.sendPort, packageConfig: await Isolate.packageConfig);
    try {
      final outcome = await Future.any([
        results.first,
        errors.first.then((e) => throw StateError('$program failed: $e')),
      ]).timeout(const Duration(minutes: 3)) as Map<Object?, Object?>;
      expect(outcome['error'], isNull, reason: 'the program threw');
      return outcome;
    } finally {
      results.close();
      errors.close();
    }
  }

  final probe = Uri.file(File('test/fixtures/client_probe.dart').absolute.path);

  group('an at_client connection names its program and SDK', () {
    test('verb', () async {
      final (client, server) = await openClient();
      await client.getRemoteSecondary()!.executeCommand('scan\n', auth: true);

      expectNamesAcmeChatAndAtClient(
          configOf(server.fromsOn(verbLookUp(client))));
    });

    test('sync', () async {
      final (client, server) = await openClient();
      final others = server.lookUpsBuilt
          .where((lookUp) =>
              !identical(lookUp, verbLookUp(client)) &&
              !identical(lookUp, monitorLookUp(client)))
          .toList();
      expect(others, hasLength(1),
          reason: 'the control: the client builds its own connection, its '
              'monitor\'s and its sync\'s, so the one left is sync\'s');
      final syncLookUp = others.single;

      client.syncService.sync();
      await server.waitUntil(() => server.fromsOn(syncLookUp).isNotEmpty,
          what: 'the sync connection authenticating');

      expectNamesAcmeChatAndAtClient(configOf(server.fromsOn(syncLookUp)));
    });

    test('notification', () async {
      final (client, server) = await openClient();
      client.notificationService.subscribe(regex: '.*');
      await server.waitUntil(() => server.monitorCount > 0,
          what: 'the monitor starting');

      expectNamesAcmeChatAndAtClient(
          configOf(server.fromsOn(monitorLookUp(client))));
    });

    test('start-up key check', () async {
      final server =
          FakeAtServer(atSign: atSign, runsClientAuthenticator: true);

      await Atsign(atSign).authenticatesAs(
          keys: keys,
          rootDomain: const AtRootDomain('127.0.0.1', 64),
          lookUps: server.lookUps,
          secondaryAddressFinder: server.addressFinder,
          particulars: AtClientParticulars()
            ..appName = 'acme_chat'
            ..appVersion = '2.3.1');

      expectNamesAcmeChatAndAtClient(configOf(server.froms));
    });
  });

  test('an app that names nothing is named after its program file', () async {
    final outcome = await runProgram(
        Uri.file(File('test/fixtures/acme_chat.dart').absolute.path));

    final config = configOf((outcome['froms'] as List).cast<String>());
    expect(config['appName'], 'acme_chat',
        reason: 'the program file is acme_chat.dart');
    expect(config['appVersion'], 'unknown');
    expect(config['sdkName'], 'atsign.dart.at_client');
    expect(config['sdkVersion'], atClientVersion);
    final warnings = (outcome['warnings'] as List)
        .cast<String>()
        .where((warning) => warning.contains('atClientParticulars'));
    expect(warnings, hasLength(1),
        reason: 'one warning when the client starts, naming '
            'atClientParticulars, however many connections it builds');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('an app with no program file to name is "unknown"', () async {
    // A data: URI is a program with no file: the isolate's Platform.script.
    final outcome = await runProgram(Uri.dataFromString(
        "import '$probe';\n"
        'void main(List<String> args, dynamic results) =>\n'
        '    openUnnamedClientAndReport(results);\n',
        mimeType: 'application/dart'));

    expect(configOf((outcome['froms'] as List).cast<String>())['appName'],
        'unknown');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('a name or version longer than 64 characters is cut', () async {
    final name = 'acme_chat_${'x' * 70}';
    final (client, server) = await openClient(appName: name);
    await client.getRemoteSecondary()!.executeCommand('scan\n', auth: true);

    expect(configOf(server.fromsOn(verbLookUp(client)))['appName'],
        name.substring(0, 64));
  });

  test(
      'Given particulars that name a platform, when the verb connection '
      'authenticates, then its from: carries the client\'s id and platform',
      () async {
    final (client, server) = await openClient(platform: 'macos');
    await client.getRemoteSecondary()!.executeCommand('scan\n', auth: true);

    final config = configOf(server.fromsOn(verbLookUp(client)));
    expect(config['clientId'],
        client.getPreferences()!.atClientParticulars.clientId,
        reason: 'the atServer tells this client\'s log lines apart by it');
    expect(config['platform'], 'macos');
  });

  test(
      'Given particulars that name no platform, when the verb connection '
      'authenticates, then its from: carries the client\'s id and no platform',
      () async {
    final (client, server) = await openClient();
    await client.getRemoteSecondary()!.executeCommand('scan\n', auth: true);

    final config = configOf(server.fromsOn(verbLookUp(client)));
    expect(config['clientId'],
        client.getPreferences()!.atClientParticulars.clientId);
    expect(config.containsKey('platform'), isFalse, reason: '$config');
  });

  test('a connection that sent no version still sends none', () async {
    final (client, server) = await openClient();
    client.notificationService.subscribe(regex: '.*');
    await server.waitUntil(() => server.monitorCount > 0,
        what: 'the monitor starting');

    final monitor = configOf(server.fromsOn(monitorLookUp(client)));
    expect(monitor.containsKey('version'), isFalse,
        reason: 'the atServer chooses its error format by version, so a '
            'connection that sent none must still send none: $monitor');
    expect(monitor['sdkName'], 'atsign.dart.at_client',
        reason:
            'the control: this is the monitor\'s config, which names at_client');
    expect(configOf(server.fromsOn(verbLookUp(client)))['version'],
        atClientVersion,
        reason: 'the verb connection still sends version, as before');
  });

  test('a proxy root\'s preamble stays bare', () async {
    final (client, server) = await openClient(rootDomain: 'proxy:127.0.0.1');
    await client.getRemoteSecondary()!.executeCommand('scan\n', auth: true);

    final froms = server.fromsOn(verbLookUp(client));
    expect(froms.first, 'from:$atSign\n',
        reason: 'a proxy routes on the atSign alone');
    expectNamesAcmeChatAndAtClient(configOf(froms.skip(1).toList()));
  });

  test(
      'Given no particulars, when authenticatesAs authenticates, then its '
      'from: names the program file and at_client', () async {
    final server = FakeAtServer(atSign: atSign, runsClientAuthenticator: true);

    await Atsign(atSign).authenticatesAs(
        keys: keys,
        rootDomain: const AtRootDomain('127.0.0.1', 64),
        lookUps: server.lookUps,
        secondaryAddressFinder: server.addressFinder);

    final programFile = Platform.script.pathSegments.last;
    expect(configOf(server.froms), {
      'appName': programFile.split('.').first,
      'appVersion': 'unknown',
      'sdkName': 'atsign.dart.at_client',
      'sdkVersion': atClientVersion,
    });
  });

  test(
      'Given an app named in its particulars, when the client starts, then it '
      'logs no warning naming atClientParticulars', () async {
    final logs = RecordedLogs()..installOn(level: 'warning');
    Iterable<String> particularsWarnings() =>
        logs.at('WARNING').where((w) => w.contains('atClientParticulars'));

    final (named, _) = await openClient();
    final afterNamed = particularsWarnings().length;
    await named.stop();
    AtClientImpl.atClientInstanceMap.clear();
    await openClient(appName: null, appVersion: null);

    expect(afterNamed, 0);
    expect(particularsWarnings(), hasLength(1),
        reason: 'the control: the recorder hears the warning an unnamed app '
            'is given');
  });

  for (final blank in ['', ' \t']) {
    test(
        'Given an appName of ${jsonEncode(blank)}, when the client starts, '
        'then it logs the warning an unnamed app is given', () async {
      final logs = RecordedLogs()..installOn(level: 'warning');

      await openClient(appName: blank);

      final warnings =
          logs.at('WARNING').where((w) => w.contains('atClientParticulars'));
      expect(warnings, hasLength(1),
          reason: 'an appName with nothing but whitespace names nothing, so '
              'the client is named after its program file');
      expect(warnings.single, contains('"unknown" where there is none'),
          reason: 'web and wasm run no program file, so the warning says '
              'what such a client is named');
    });
  }
}
