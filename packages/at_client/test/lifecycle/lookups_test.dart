import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:at_demo_data/at_demo_data.dart' as demo;

import '../test_utils/ml_dsa_keyfile.dart';
import '../test_utils/mocks.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// The communications leg of the platform bundle: the factory an application
/// hands the verbs builds every connection the client opens, not just the
/// client's own.
void main() {
  late Directory dir;
  late List<({String atSign, bool authenticated})> asked;
  late List<MockAtLookupImpl> built;

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
    registerFallbackValue(AtKey());
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lookups_');
    asked = [];
    built = [];
    AtClientManager.getInstance().reset();
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientManager.getInstance().reset();
    dir.deleteSync(recursive: true);
  });

  /// A factory that records what it was asked for and hands back a mock,
  /// one per call, so each connection the client opens can be told apart.
  AtLookupMuxable recording({
    required String atSign,
    required AtRootDomain rootDomain,
    required AtAuthenticator? authenticator,
    SecondaryAddressFinder? secondaryAddressFinder,
    Map<String, dynamic> clientConfig = const {},
  }) {
    final lookUp = MockAtLookupImpl();
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);
    when(() => lookUp.close()).thenAnswer((_) async {});
    // the bridge reads the enrollment id off the lookup until the ladder goes
    // ignore: deprecated_member_use
    when(() => lookUp.enrollmentId).thenReturn(null);
    when(() =>
            lookUp.pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')))
        .thenAnswer((_) async => true);
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      if (command.startsWith('enroll:request:')) {
        return 'data:${jsonEncode({
              'enrollmentId': 'e1',
              'status': 'pending'
            })}';
      }
      return 'data:null';
    });
    when(() => lookUp.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first;
      if (builder is LookupVerbBuilder && builder.atKey.key == 'publicKey') {
        return 'data:${demo.encryptionPublicKeyMap['@alice🛠']}';
      }
      throw StateError('the mocked atServer has no answer for: '
          '${(builder as VerbBuilder).buildCommand()}');
    });
    asked.add((atSign: atSign, authenticated: authenticator != null));
    built.add(lookUp);
    return lookUp;
  }

  AtClientPreference preference() => AtClientPreference()
    ..hiveStoragePath = dir.path
    ..namespace = 'wavi'
    ..monitorAutoStart = false;

  test(
      'every connection a client opens comes from the factory: its own, '
      'sync\'s, the monitor\'s', () async {
    final client = await buildAtClient(
        atSign: '@lookups',
        namespace: 'wavi',
        preference: preference(),
        lookUps: recording) as AtClientImpl;

    expect(client.getRemoteSecondary()!.atLookUp, same(built.first),
        reason: 'the client\'s own connection');
    final sync = SyncServiceImpl.remoteSecondaryFor(client);
    expect(built, contains(same(sync.atLookUp)),
        reason: 'sync builds its own connection, and asks the same factory; '
            'a mock injected through atLookUp: never reached this one');
    final monitor =
        (client.notificationService as NotificationServiceImpl).monitor.lookUp;
    expect(built, contains(same(monitor)),
        reason: 'the monitor\'s connection, likewise');
    expect(asked.map((a) => a.atSign).toSet(), {'@lookups'});
    expect(built, hasLength(greaterThanOrEqualTo(3)));
  });

  test('a client built with no factory opens TLS connections (control)',
      () async {
    final client = await buildAtClient(
        atSign: '@nofactory',
        namespace: 'wavi',
        preference: preference()) as AtClientImpl;

    expect(client.getRemoteSecondary()!.atLookUp, isA<AtLookupImpl>());
    expect(
        client.lookUps(
            atSign: '@nofactory',
            rootDomain: const AtRootDomain('127.0.0.1', 64),
            authenticator: null),
        isA<AtLookupImpl>());
    expect(built, isEmpty);
  });

  test(
      'open hands the factory through, and the probe authenticates on what '
      'it built', () async {
    final client = await Atsign('@opened').open(
        keys: await typedKeyfile('@opened', enrollmentId: 'primary'),
        preference: preference(),
        lookUps: recording);

    expect(client.connection.current.isOnline, isTrue,
        reason: 'the factory\'s mock said yes to the PKAM');
    expect(client.getRemoteSecondary()!.atLookUp, same(built.first));
  });

  test('enroll submits on a connection the factory built, unauthenticated',
      () async {
    final pending = await Atsign('@enrolls').enroll(
        otp: 'ABC123',
        app: 'wavi',
        device: 'phone',
        namespaces: {'wavi': 'rw'},
        keys: InMemoryAtKeysIo(),
        preference: preference(),
        lookUps: recording);

    expect(pending.enrollmentId, 'e1');
    expect(asked, [(atSign: '@enrolls', authenticated: false)],
        reason: 'one connection, for the submission, with no credential: '
            'this device holds none yet');
    verify(() => built.single.close()).called(1);
  });
}
