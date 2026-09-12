import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/ml_dsa_keyfile.dart';
import '../test_utils/mocks.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// `Atsign.open`: a client comes back online, offline or refused, and the
/// first open of a principal on a device is the one refusal that throws.
///
/// The atServer is a mocked lookup handed in through `atLookUp`, so what it
/// answers to the PKAM attempt is the test's to choose; the offline case uses
/// a real connect to a port nothing listens on.
void main() {
  late Directory dir;

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('open_');
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    dir.deleteSync(recursive: true);
  });

  Future<int> refusedPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<AtClientPreference> preference() async => AtClientPreference()
    ..rootDomain = InternetAddress.loopbackIPv4.address
    ..rootPort = await refusedPort()
    ..hiveStoragePath = dir.path
    ..namespace = 'lifecycle';

  /// A lookup whose PKAM attempt does what [onPkam] says.
  MockAtLookupImpl lookUpAnswering(Future<bool> Function() onPkam) {
    final lookUp = MockAtLookupImpl();
    when(() => lookUp.pkamAuthenticate(
        enrollmentId: any(named: 'enrollmentId'))).thenAnswer((_) => onPkam());
    when(() => lookUp.close()).thenAnswer((_) async {});
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);
    return lookUp;
  }

  test('a client built and not yet asked says so', () async {
    final client = await buildAtClient(
        atSign: '@unattempted',
        namespace: 'lifecycle',
        preference: await preference(),
        atKeysIo: await typedKeyfile('@unattempted', enrollmentId: 'primary'));
    final state = client.connection.current;
    expect(state.outcome, AtConnectionOutcome.offline);
    expect(state.cause, AtConnectionCause.unattempted,
        reason: 'nothing has tried, and the state does not pretend otherwise');
  });

  test('no atServer reachable yields a client in the offline state', () async {
    const atSign = '@offline';
    final client = await Atsign(atSign).open(
        keys: await typedKeyfile(atSign, enrollmentId: 'primary'),
        preference: await preference());

    final state = client.connection.current;
    expect(state.isOffline, isTrue);
    expect(state.cause, AtConnectionCause.unreachable);
    expect(state.error, isA<RootServerConnectivityException>(),
        reason: 'the attempt reached the atDirectory step and the refusal is '
            'carried typed, not as text');
    expect(await (client as AtClientImpl).hasBeenOnline(), isFalse);
  });

  test('the atServer accepting the credentials yields online, and the device '
      'remembers having been online as this principal', () async {
    const atSign = '@online';
    final client = await Atsign(atSign).open(
        keys: await typedKeyfile(atSign, enrollmentId: 'primary'),
        preference: await preference(),
        atLookUp: lookUpAnswering(() async => true));

    expect(client.connection.current.isOnline, isTrue);
    expect(await (client as AtClientImpl).hasBeenOnline(), isTrue,
        reason: 'open returns after the marker is written, so a later '
            'refusal on this device hands back a client');
  });

  test('a refusal on a device that has never been online throws, and leaves '
      'nothing behind', () async {
    const atSign = '@refusedfirst';
    final revoked = lookUpAnswering(() async => throw UnAuthenticatedException(
        'Failed connecting to $atSign. error:AT0027:Apkam Access Revoked'));

    await expectLater(
        () async => Atsign(atSign).open(
            keys: await typedKeyfile(atSign, enrollmentId: 'primary'),
            preference: await preference(),
            atLookUp: revoked),
        throwsA(isA<AtOpenRefusedException>()
            .having((e) => e.state.cause, 'cause', AtConnectionCause.revoked)
            .having((e) => e.atSign, 'atSign', atSign)),
        reason: 'with nothing held locally there is nothing to serve');
    expect(AtClientImpl.holdsLiveClient(atSign), isFalse,
        reason: 'the part-built client was stopped and unfiled');
  });

  test('an atSign the atDirectory has no atServer for counts as a refusal on '
      'first open', () async {
    const atSign = '@noserver';
    final missing = lookUpAnswering(() async =>
        throw SecondaryNotFoundException('No entry in atDirectory for noserver'));

    await expectLater(
        () async => Atsign(atSign).open(
            keys: await typedKeyfile(atSign, enrollmentId: 'primary'),
            preference: await preference(),
            atLookUp: missing),
        throwsA(isA<AtOpenRefusedException>().having(
            (e) => e.state.cause, 'cause', AtConnectionCause.noAtServer)));
  });

  test('a refusal on a device that has been online comes back as a client in '
      'the refused state', () async {
    const atSign = '@refusedlater';
    final pref = await preference();
    final keys = await typedKeyfile(atSign, enrollmentId: 'primary');

    final first = await Atsign(atSign)
        .open(keys: keys, preference: pref, atLookUp: lookUpAnswering(() async => true));
    expect(first.connection.current.isOnline, isTrue);
    await first.stop();

    final revoked = lookUpAnswering(() async => throw UnAuthenticatedException(
        'Failed connecting to $atSign. error:AT0027:Apkam Access Revoked'));
    final second =
        await Atsign(atSign).open(keys: keys, preference: pref, atLookUp: revoked);

    final state = second.connection.current;
    expect(state.isRefused, isTrue,
        reason: 'the store holds what this principal synced while online, '
            'and the application decides what to do with a revoked device');
    expect(state.cause, AtConnectionCause.revoked);
    expect(state.error, isA<UnAuthenticatedException>());
  });

  test('a verb that comes back moves the state to online, and changes '
      'reports it', () async {
    const atSign = '@flips';
    final lookUp = lookUpAnswering(() async => throw RootServerConnectivityException(
        'Connecting to 127.0.0.1:1 : SocketException: Connection refused'));
    final client = await Atsign(atSign).open(
        keys: await typedKeyfile(atSign, enrollmentId: 'primary'),
        preference: await preference(),
        atLookUp: lookUp);
    expect(client.connection.current.isOffline, isTrue);

    final flipped = expectLater(
        client.connection.changes,
        emits(isA<AtConnectionState>()
            .having((s) => s.isOnline, 'isOnline', isTrue)));
    when(() => lookUp.executeVerb(any()))
        .thenAnswer((_) async => 'data:[]');
    await client.getRemoteSecondary()!.executeVerb(ScanVerbBuilder());
    await flipped;
    expect(client.connection.current.isOnline, isTrue);
  });

  test('attempt() tries again now and reports what it found', () async {
    const atSign = '@retry';
    var reachable = false;
    final lookUp = lookUpAnswering(() async {
      if (!reachable) {
        throw SecondaryConnectException(
            'unable to connect to atServer for $atSign on h:1');
      }
      return true;
    });
    final client = await Atsign(atSign).open(
        keys: await typedKeyfile(atSign, enrollmentId: 'primary'),
        preference: await preference(),
        atLookUp: lookUp);
    expect(client.connection.current.cause, AtConnectionCause.unreachable);

    reachable = true;
    final state = await client.connection.attempt();
    expect(state.isOnline, isTrue);
    expect(client.connection.current.isOnline, isTrue);
  });
}
