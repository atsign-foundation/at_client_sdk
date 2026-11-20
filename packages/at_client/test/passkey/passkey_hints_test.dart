// Scenarios: features/at_client/passkey_hints.feature. Each test is named after its scenario.
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_chops/at_chops.dart' show AESKey;
import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart' show InMemoryAtClientStorage;
import 'package:at_client/passkey.dart';
import 'package:at_client/src/passkey/enrollment_pointer_store.dart'
    show enrollmentPointerKey;
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show withApkamKey;
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';
import '../support/custody_fakes.dart';
import '../support/passkey_at_server.dart';
import '../test_utils/recorded_logs.dart';

const _atSign = '@alice🛠';
const _cram = 'cram-secret';
const _eid = 'e1d2c3';
const _root = AtRootDomain('root.test', 64);

/// An enrollment id outside the enrollment id alphabet.
const _outsideAlphabet = 'bad id/..';

/// The PRF output of the first passkey the test authenticator registers.
Uint8List _firstPrf() => Uint8List.fromList(List.generate(32, (i) => i));

void main() {
  final logs = RecordedLogs();
  setUpAll(logs.installOn);
  late PasskeyAtServer server;
  late FakeAuthenticator authenticator;
  late List<PasskeySession> sessions;

  /// Activates [_atSign] as enrollment [_eid] with the passkey's pair, as an
  /// atServer's CRAM activation does: only while the CRAM secret is live.
  Future<AtKeys> activate(
      {required String atSign,
      required String cram,
      required ApkamKeyPair apkamKeyPair}) async {
    if (cram != _cram || !server.cramLive) {
      throw AtException('the CRAM secret is not live');
    }
    server.apkamKeys[_eid] = apkamKeyPair.publicKey;
    final keys = AtKeys.legacy(
        encryptionPublicKey: base64Encode(utf8.encode('enc-pub')),
        encryptionPrivateKey: base64Encode(utf8.encode('enc-priv')),
        selfEncryptionKey: AESKey.generate(32).key)
      ..atsign = atSign.toAtsign();
    return withApkamKey(keys, _eid, apkamKeyPair);
  }

  Future<AtClient> openClient(
          {required AtLookupMuxable lookUp,
          required String atSign,
          required String enrollmentId,
          required WrittenAtKeysIo keysIo}) =>
      Atsign(atSign).open(
          keys: keysIo,
          preference: AtClientPreference()
            ..namespace = 'wavi'
            ..rootDomain = _root.rootDomain
            ..rootPort = _root.rootPort
            ..remoteLocalPref = RemoteLocalPref.remoteOnly
            ..monitorAutoStart = false,
          namespace: 'wavi',
          storage:
              InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
          atLookUp: lookUp,
          lookUps: server.lookUps,
          secondaryAddressFinder: server.finder);

  PasskeyCustody custody(FakeHints hints) => PasskeyCustody(
      prf: PasskeyPrf(authenticator),
      deriver: const BytesPasskeyKeyDeriver(),
      pointerReader: LookupEnrollmentPointerReader(
          lookUps: server.lookUps,
          rootDomain: _root,
          secondaryAddressFinder: server.finder),
      gateway: AtAuthEnrollmentGateway(
          lookUps: server.lookUps,
          finder: server.finder,
          root: _root,
          app: 'wavi',
          device: 'browser',
          clientOpener: openClient,
          activator: activate),
      hints: hints,
      retryDelay: Duration.zero,
      setupLock: FakeSetupLock(),
      setupLockPrefix: 'test:setup');

  /// Onboards [_atSign] with a new passkey, remembering it in [hints], and
  /// stops the session; returns the new enrollment's id.
  Future<String> onboarded(FakeHints hints) async {
    final session = await custody(hints).onboard(atSign: _atSign, cram: _cram);
    final enrollmentId = session.client.enrollmentId!;
    await session.stop();
    return enrollmentId;
  }

  PasskeySession kept(PasskeySession session) {
    sessions.add(session);
    return session;
  }

  /// The derived names and vault of the first passkey.
  Future<DerivedKeys> firstPasskey() async {
    final keys = await DerivedKeys.derive(_firstPrf(), _atSign);
    addTearDown(keys.vault.close);
    return keys;
  }

  /// The atServer key of the first passkey's pointer.
  Future<String> pointerKey() async {
    final keys = await firstPasskey();
    return enrollmentPointerKey(_atSign, keys.lookupHex, ns: keys.ns);
  }

  /// The enrollment id the first passkey's pointer names.
  Future<String> pointedEnrollmentId() async {
    final keys = await firstPasskey();
    return (await keys.vault.open(PasskeyRecordType.eid,
            server.records['public:${await pointerKey()}']!))['enrollmentId']
        as String;
  }

  /// The commands every connection sent from command [from] on.
  List<String> commandsFrom(int from) => [
        for (final c in server.commands.skip(from))
          c.substring(c.indexOf(': ') + 2)
      ];

  List<String> pkams(int from) =>
      commandsFrom(from).where((c) => c.startsWith('pkam:')).toList();

  Iterable<String> warnings(String saying) =>
      logs.at('WARNING').where((m) => m.contains(saying));

  setUp(() {
    server = PasskeyAtServer(_atSign);
    authenticator = FakeAuthenticator();
    sessions = [];
    logs.records.clear();
  });

  tearDown(() async {
    for (final session in sessions) {
      await session.stop();
    }
  });

  test(
      'A login whose passkey hints cannot be written returns its session, and '
      'the next login writes them', () async {
    final enrollmentId = await onboarded(FakeHints());
    final device = FakeHints()
      ..failWrites = true
      ..writeFailure = HintStoreException('quota exceeded writing $_eid');

    final session = kept(await custody(device).open(atSign: _atSign));

    expect(session.client.connection.current.isOnline, isTrue);
    expect(session.client.enrollmentId, enrollmentId);
    await session.stop();
    expect(device.credentials, isEmpty,
        reason: 'the control: the write of the hints failed');
    expect(device.ids, isEmpty,
        reason: 'the control: the write of the hints failed');
    final warned = warnings('were not saved').toList();
    expect(warned, hasLength(1));
    expect(
        warned.single,
        allOf(
            contains(_atSign),
            contains('passkey hints'),
            contains('were not saved after the login'),
            contains('HintStoreException')));
    expect(warned.single, isNot(contains(_eid)),
        reason: 'the warning carries no enrollment id');
    expect(warned.single, isNot(contains('quota exceeded')),
        reason: "the warning carries no exception's message");

    device.failWrites = false;
    kept(await custody(device).open(atSign: _atSign));

    expect(device.ids, {_atSign: enrollmentId});
    expect(device.credentials, {_atSign: authenticator.current});
  });

  test(
      'An onboarding whose passkey hints cannot be written returns its session',
      () async {
    final device = FakeHints()
      ..failWrites = true
      ..writeFailure = HintStoreException('quota exceeded writing $_eid');

    final session =
        kept(await custody(device).onboard(atSign: _atSign, cram: _cram));

    expect(session.client.connection.current.isOnline, isTrue);
    expect(session.client.enrollmentId, _eid,
        reason: 'the enrollment the activation created');
    expect(server.cramLive, isFalse, reason: 'the CRAM secret is deleted');
    expect(server.records['public:publickey$_atSign'],
        base64Encode(utf8.encode('enc-pub')),
        reason: 'the encryption public key is published');
    expect(device.credentials, isEmpty);
    expect(device.ids, isEmpty);
    final warned = warnings('were not saved').toList();
    expect(warned, hasLength(1));
    expect(
        warned.single,
        allOf(
            contains(_atSign),
            contains('were not saved after the onboarding'),
            contains('HintStoreException')));
    expect(warned.single, isNot(contains(_eid)));
    expect(warned.single, isNot(contains('quota exceeded')));
  });

  test(
      'A hint write that fails with an Error, not an Exception, still fails '
      'the login', () async {
    await onboarded(FakeHints());
    final broken = StateError('the hint store is broken');
    final device = FakeHints()
      ..failWrites = true
      ..writeFailure = broken;
    final firstSocket = server.sockets.length;

    final opening = custody(device).open(atSign: _atSign);
    addTearDown(() => opening.then((s) => s.stop(), onError: (Object _) {}));

    await expectLater(opening, throwsA(same(broken)));

    final authenticated = [
      for (var i = firstSocket; i < server.sockets.length; i++)
        if (server.on(i).any((c) => c.startsWith('pkam:'))) server.sockets[i]
    ];
    expect(authenticated, hasLength(1),
        reason: 'the login authenticated its enrollment on one connection');
    expect(authenticated.single.destroyed, isTrue,
        reason: "the enrollment's session is closed");
  });

  test('A remembered enrollment id that cannot be read counts as no hints',
      () async {
    final saved = FakeHints();
    await onboarded(saved);
    final device = FakeHints()
      ..credentials.addAll(saved.credentials)
      ..ids.addAll(saved.ids)
      ..enrollmentIdReadFailure =
          HintStoreException('cannot read enrollment $_eid');
    expect(device.ids, {_atSign: _eid},
        reason: 'the control: this device remembers the passkey');
    authenticator.gets = 0;
    final mark = server.commands.length;

    final session = kept(await custody(device).open(atSign: _atSign));

    expect(authenticator.gets, 1);
    expect(authenticator.lastAllowCredential, isNull,
        reason: 'the login asserts any passkey');
    expect(commandsFrom(mark), contains('lookup:${await pointerKey()}'),
        reason: "the login reads the passkey's pointer");
    expect(session.client.connection.current.isOnline, isTrue);
    expect(session.client.enrollmentId, await pointedEnrollmentId());
    final warned = warnings('could not be read').toList();
    expect(warned, hasLength(1), reason: 'the login warns once');
    expect(
        warned.single,
        allOf(contains(_atSign), contains('remembered enrollment id'),
            contains('HintStoreException')));
    expect(warned.single, isNot(contains(_eid)),
        reason: 'the warning carries no enrollment id');
    expect(warned.single, isNot(contains('cannot read')),
        reason: "the warning carries no exception's message");
  });

  test('A remembered credential id that cannot be read counts as no hints',
      () async {
    final saved = FakeHints();
    await onboarded(saved);
    final credentialId = saved.credentials[_atSign]!;
    final device = FakeHints()
      ..credentials.addAll(saved.credentials)
      ..ids.addAll(saved.ids)
      ..credentialIdReadFailure =
          HintStoreException('cannot read credential $credentialId');
    expect(device.ids, {_atSign: _eid},
        reason: 'the control: this device remembers the passkey');
    authenticator.gets = 0;
    final mark = server.commands.length;

    final session = kept(await custody(device).open(atSign: _atSign));

    expect(authenticator.gets, 1);
    expect(authenticator.lastAllowCredential, isNull,
        reason: 'the login asserts any passkey');
    expect(commandsFrom(mark), contains('lookup:${await pointerKey()}'),
        reason: "the login reads the passkey's pointer");
    expect(session.client.connection.current.isOnline, isTrue);
    expect(session.client.enrollmentId, await pointedEnrollmentId());
    final warned = warnings('could not be read').toList();
    expect(warned, hasLength(1), reason: 'the login warns once');
    expect(
        warned.single,
        allOf(contains(_atSign), contains('remembered credential id'),
            contains('HintStoreException')));
    expect(warned.single, isNot(contains('$credentialId')),
        reason: 'the warning carries no credential id');
    expect(warned.single, isNot(contains('cannot read')),
        reason: "the warning carries no exception's message");
  });

  test(
      'A remembered enrollment id outside the enrollment id alphabet counts '
      'as no hints', () async {
    final saved = FakeHints();
    await onboarded(saved);
    final device = FakeHints()
      ..credentials.addAll(saved.credentials)
      ..ids[_atSign] = _outsideAlphabet;
    authenticator.gets = 0;
    final mark = server.commands.length;

    final session = kept(await custody(device).open(atSign: _atSign));

    expect(authenticator.gets, 1);
    expect(authenticator.lastAllowCredential, isNull,
        reason: 'the login asserts any passkey');
    expect(commandsFrom(mark), contains('lookup:${await pointerKey()}'),
        reason: "the login reads the passkey's pointer");
    final pointed = await pointedEnrollmentId();
    expect(pkams(mark), isNotEmpty, reason: 'the control: the login sent PKAM');
    expect(pkams(mark), everyElement(contains('enrollmentId:$pointed:')),
        reason: 'every PKAM names the pointed enrollment, none the '
            'remembered id');
    expect(session.client.connection.current.isOnline, isTrue);
    expect(session.client.enrollmentId, pointed);
    expect(device.ids, {_atSign: pointed}, reason: 'the hints are replaced');
    final warned = warnings('outside the enrollment id alphabet').toList();
    expect(warned, hasLength(1), reason: 'the login warns once');
    expect(warned.single,
        allOf(contains(_atSign), contains('remembered enrollment id')));
    expect(
        logs.at('WARNING').where((m) => m.contains(_outsideAlphabet)), isEmpty,
        reason: 'no warning carries the remembered id');
  });

  test(
      'An enrollment id the pointer holds outside the enrollment id alphabet '
      'is a lost passkey', () async {
    await onboarded(FakeHints());
    final keys = await firstPasskey();
    server.records['public:${await pointerKey()}'] = await keys.vault
        .seal(PasskeyRecordType.eid, {'enrollmentId': _outsideAlphabet});
    final mark = server.commands.length;

    final opening = custody(FakeHints()).open(atSign: _atSign);
    addTearDown(() => opening.then((s) => s.stop(), onError: (Object _) {}));

    await expectLater(opening, throwsA(isA<PasskeyLostException>()));

    expect(commandsFrom(mark), contains('lookup:${await pointerKey()}'),
        reason: 'the control: the login read the pointer');
    expect(pkams(mark), isEmpty, reason: 'no PKAM is sent');
  });
}
