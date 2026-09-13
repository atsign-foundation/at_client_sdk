import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/factory/service_factories.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';

import 'lifecycle_rig.dart';

/// `AtOnboardingServiceImpl.authenticate()`: the client is opened from the
/// keyfile the preference names, made the manager's current client, and the
/// answer is whether its connection is online.
///
/// The atServer is a mocked lookup handed to the service, so what it answers
/// to the PKAM attempt is the test's to choose.
void main() {
  AtSignLogger.root_level = 'SHOUT';
  const atSign = '@alice🛠';
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cli_authenticate_');
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
    dir.deleteSync(recursive: true);
  });

  /// A legacy-posture preference over the test keyfile. The posture is named
  /// rather than inherited: a post-quantum posture retrofits a legacy keyfile
  /// at start, which the mocked atServer does not model.
  Future<AtOnboardingPreference> preference() async =>
      AtOnboardingPreference(posture: PqPosture.legacy)
        ..atKeysFilePath = 'test/data/@alice🛠_key.atKeys'
        ..namespace = 'unit_test'
        ..rootDomain = InternetAddress.loopbackIPv4.address
        ..rootPort = await refusedPort()
        ..storagePath = dir.path;

  test(
      'answers true when the atServer accepts the PKAM, and the manager holds '
      'the client', () async {
    final service = AtOnboardingServiceImpl(atSign, await preference(),
        atLookUp: lookUpAnswering(() async => true));

    expect(await service.authenticate(), isTrue);

    final client = service.atClient!;
    expect(client.connection.current.isOnline, isTrue);
    expect(identical(AtClientManager.getInstance().atClient, client), isTrue,
        reason: 'the adapter\'s job is to leave the manager holding the '
            'client it opened');
    expect(client.atKeysIo, isNotNull,
        reason: 'the client reads its keys from the keyfile the preference '
            'named');
    expect(client.getCurrentAtSign(), atSign);
  });

  test(
      'answers false for an atServer it cannot reach, keeping the offline '
      'client', () async {
    final service = AtOnboardingServiceImpl(atSign, await preference(),
        atLookUp: lookUpAnswering(() async => throw SecondaryConnectException(
            'unable to connect to atServer for $atSign on h:1')));

    expect(await service.authenticate(), isFalse);

    expect(service.atClient, isNotNull,
        reason: 'an offline client serves what it holds locally');
    expect(service.atClient!.connection.current.cause,
        AtConnectionCause.unreachable);
  });

  test(
      'answers false, holding no client, when the atServer refuses a first '
      'open', () async {
    final service = AtOnboardingServiceImpl(atSign, await preference(),
        atLookUp: lookUpAnswering(() async => throw UnAuthenticatedException(
            'Failed connecting to $atSign. error:AT0401:Client authentication '
            'failed')));

    expect(await service.authenticate(), isFalse);

    expect(service.atClient, isNull);
    expect(AtClientImpl.holdsLiveClient(atSign), isFalse);
  });

  test('a second call stops the client the first opened and opens another',
      () async {
    final service = AtOnboardingServiceImpl(atSign, await preference(),
        atLookUp: lookUpAnswering(() async => true));
    expect(await service.authenticate(), isTrue);
    final first = service.atClient as AtClientImpl;

    expect(await service.authenticate(), isTrue);

    expect(first.isStopped, isTrue);
    expect(identical(service.atClient, first), isFalse);
    expect(identical(AtClientManager.getInstance().atClient, service.atClient),
        isTrue);
  });

  test('skipSync gives the client a sync service that does nothing', () async {
    final service = AtOnboardingServiceImpl(
        atSign, (await preference())..skipSync = true,
        atLookUp: lookUpAnswering(() async => true));

    expect(await service.authenticate(), isTrue);

    expect(service.atClient!.syncService, isA<NoOpSyncService>());
  });

  test('a preference naming no keyfile gets the home directory\'s', () {
    final preference = AtOnboardingPreference()..atKeysFilePath = null;

    AtOnboardingServiceImpl(atSign, preference);

    expect(preference.atKeysFilePath,
        endsWith('${Platform.pathSeparator}${atSign}_key.atKeys'));
    expect(preference.atKeysFilePath, contains('.atsign'));
  });
}
