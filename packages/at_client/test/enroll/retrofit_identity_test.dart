import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/enroll/self_retrofit.dart' show retrofitIdentity;
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// A store whose writes never land: every read hands back a fresh copy of
/// what it was created holding, and a flush is recorded and dropped. The
/// shape of a keychain or file whose write failed silently.
class _StaleKeysIo extends WrittenAtKeysIo {
  final AtKeys _held;
  int flushes = 0;

  _StaleKeysIo(this._held);

  @override
  FutureOr<AtKeys> read(String atsign) => AtKeys.fromJson(_held.toJson());

  @override
  Future<void> write(String atsign, AtKeys atKeys) async =>
      throw StateError('the stale store holds keys already');

  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) {
    flushes++;
  }
}

/// `retrofitIdentity`: the identity half of a self-retrofit files the new
/// enrollment into the keyfile and hands back a session naming it, without
/// authenticating. The keyfile is the authority on which enrollment the
/// client now runs as, and a keyfile that disagrees with the atServer's
/// answer is a refusal, not a session.
///
/// The atServer is a mocked lookup answering by verb.
void main() {
  const atSign = '@alice🛠';
  const legacyId = 'first-1';
  const newId = 'retro-2';

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
  });

  /// A pre-retrofit keyfile: rsa2048 in the flat fields, enrolled as
  /// [legacyId].
  AtKeys legacyKeys() => AtKeys()
    // ignore: deprecated_member_use
    ..apkamPublicKey = AtBytes.fromString(demo.pkamPublicKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..apkamPrivateKey = AtBytes.fromString(demo.pkamPrivateKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..defaultEncryptionPublicKey =
        AtBytes.fromString(demo.encryptionPublicKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..defaultEncryptionPrivateKey =
        AtBytes.fromString(demo.encryptionPrivateKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..defaultSelfEncryptionKey = AtBytes.fromString(demo.aesKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..enrollmentId = legacyId;

  /// An atServer that auto-approves the self-enrollment as [newId] and
  /// records every command it was sent.
  ({MockAtLookupImpl lookUp, List<String> sent}) atServer() {
    final lookUp = MockAtLookupImpl();
    final sent = <String>[];
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      sent.add(command);
      if (command.startsWith('enroll:')) {
        return 'data:${jsonEncode({
              'enrollmentId': newId,
              'status': 'approved'
            })}';
      }
      throw StateError('the mocked atServer has no answer for: $command');
    });
    when(() => lookUp.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first as VerbBuilder;
      throw StateError('the mocked atServer has no answer for: '
          '${builder.buildCommand()}');
    });
    return (lookUp: lookUp, sent: sent);
  }

  AtClientPreference preference() => AtClientPreference()
    ..rootDomain = InternetAddress.loopbackIPv4.address
    ..rootPort = 1
    ..namespace = 'lifecycle';

  Future<AtAuthSession> retrofit(WrittenAtKeysIo keys, MockAtLookupImpl lookUp,
          {String? namespace = 'lifecycle'}) =>
      retrofitIdentity(
          session: AtAuthSession(
              atSign: atSign,
              rootDomain: const AtRootDomain('127.0.0.1', 1),
              atKeysIo: keys,
              namespace: namespace,
              enrollmentId: legacyId),
          atLookUp: lookUp,
          preference: preference(),
          appName: 'wavi',
          deviceName: 'laptop',
          namespaces: const {'*': 'rw', '__manage': 'rw'},
          signingAlgo: SigningAlgoType.mldsa65);

  test(
      'files the new enrollment, names it on the session, and does not '
      'authenticate', () async {
    final store = InMemoryAtKeysIo.holding(atSign, legacyKeys());
    final server = atServer();

    final session = await retrofit(store, server.lookUp);

    expect(session.enrollmentId, newId);
    expect(session.atSign, atSign);
    expect(session.namespace, 'lifecycle');
    expect(session.atKeysIo, same(store),
        reason: 'the caller re-derives its keys from the store it named');

    final keys = await store.read(atSign);
    expect(keys.enrollmentToAuthenticateAs(), newId,
        reason: 'the keyfile is what decides which enrollment the next '
            'connection authenticates as');
    expect(keys.signingAlgorithmForEnrollment(newId), SigningAlgoType.mldsa65);
    // ignore: deprecated_member_use
    expect(keys.enrollmentId, legacyId,
        reason: 'the flat fields keep the legacy enrollment, never-lose');

    final enrollCommand =
        server.sent.where((c) => c.startsWith('enroll:')).single;
    expect(
        enrollCommand,
        allOf(contains('"appName":"wavi"'), contains('"deviceName":"laptop"'),
            contains('"signingAlgo":"mldsa65"')));
    verifyNever(() => server.lookUp
        .pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')));
  });

  test('the client\'s namespace fills a session that names none', () async {
    final store = InMemoryAtKeysIo.holding(atSign, legacyKeys());
    final session = await retrofit(store, atServer().lookUp, namespace: null);
    expect(session.namespace, 'lifecycle',
        reason: 'a client built without one runs none of its start-time '
            'self-heal');
  });

  test('a store whose write did not land is refused, naming both enrollments',
      () async {
    final stale = _StaleKeysIo(legacyKeys());
    final server = atServer();

    await expectLater(
        () => retrofit(stale, server.lookUp),
        throwsA(isA<AtClientException>().having(
            (e) => e.message,
            'message',
            allOf(
                contains('authenticates as $legacyId'),
                contains('retrofitting to $newId'),
                contains('legacy client is untouched')))));
    expect(stale.flushes, 1,
        reason: 'the write was attempted, and the read-back is what caught it');
    expect(server.sent.where((c) => c.startsWith('enroll:')), hasLength(1),
        reason: 'the atServer holds an approved enrollment nobody can use, '
            'which a rerun replaces rather than reuses');
  });
}
