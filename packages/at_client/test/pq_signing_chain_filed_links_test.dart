// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/client/pq_client_bootstrap.dart';
import 'package:at_client/src/enroll/privilege_resolver.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';

class _Unprivileged implements EnrollmentPrivilegeResolver {
  @override
  Future<bool> isFullyPrivileged() async => false;
  @override
  Future<bool> isEnrollmentFullyPrivileged(String enrollmentId) async => false;
}

/// A link conveyed to an enrollment waits in its keyfile entry until it is
/// stamped, so a restart before the stamp does not lose it.
void main() {
  const atSign = '@alice';
  late Map<String, String> remoteData;
  late Map<String, Metadata> remoteMetadata;

  setUpAll(() => registerFallbackValue(AtKey()));
  setUp(() {
    remoteData = {};
    remoteMetadata = {};
  });

  MockAtClient client(String enrollmentId) => buildRemoteBackedMockClient(
      atSign: atSign,
      enrollmentId: enrollmentId,
      remoteData: remoteData,
      remoteMetadata: remoteMetadata);

  Future<AtClientSecretSharing> registered(MockAtClient c) async {
    final sharing = AtClientSecretSharing.forClient(c);
    await sharing.register();
    return sharing;
  }

  /// [c]'s key source: a keyfile holding an entry for [enrollmentId] unless
  /// [withEntry] is false.
  Future<InMemoryAtKeysIo> keyfileFor(MockAtClient c, String enrollmentId,
      {bool withEntry = true}) async {
    final io = InMemoryAtKeysIo();
    final keys = AtKeys(atsign: atSign.toAtsign());
    if (withEntry) keys.recordEnrollmentSnapshot(enrollmentId, appName: 'app');
    await io.write(atSign, keys);
    when(() => c.atKeysIo).thenReturn(io);
    return io;
  }

  /// The same enrollment after a restart: a new client over the same keyfile,
  /// whose secret store holds nothing.
  MockAtClient restarted(String enrollmentId, AtKeysIo io) {
    final c = client(enrollmentId);
    when(() => c.atKeysIo).thenReturn(io);
    return c;
  }

  Secret chainLinkSecret(SignedEnvelope link) => Secret(
      namespace: 'buzz',
      name: PqSigningChain.linkSecretName,
      value: PqSigningChain.encodeLink(link.toJson()));

  Future<Map<String, dynamic>?> filed(AtKeysIo io, String field) async =>
      (await io.read(atSign)).linkFor('child-1', field);

  /// A chain link for `child-1`, signed by `parent-1`, with both registered.
  Future<({MockAtClient child, SignedEnvelope link})> signedChainLink() async {
    final parentClient = client('parent-1');
    final parent = await registered(parentClient);
    final childClient = client('child-1');
    await registered(childClient);
    final link =
        await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
    return (child: childClient, link: link!);
  }

  test('a conveyed link is filed into its enrollment\'s keyfile entry',
      () async {
    final signed = await signedChainLink();
    final io = await keyfileFor(signed.child, 'child-1');

    expect(
        await PqSigningChain(signed.child)
            .fileConveyedLink(chainLinkSecret(signed.link)),
        isTrue);

    expect(await filed(io, PqSigningChain.linkField),
        jsonDecode(jsonEncode(signed.link.toJson())));
  });

  test('a filed link is stamped after a restart, then dropped from the keyfile',
      () async {
    final signed = await signedChainLink();
    final io = await keyfileFor(signed.child, 'child-1');
    await PqSigningChain(signed.child)
        .fileConveyedLink(chainLinkSecret(signed.link));
    expect(await filed(io, PqSigningChain.linkField), isNotNull,
        reason: 'the premise: the link is filed');

    final after = restarted('child-1', io);
    expect(await PqSigningChain(after).publishPendingLink(), isTrue,
        reason: 'the secret store is empty after a restart, so only the '
            'keyfile still holds the link');

    expect(await PqSigningChain(after).readLink('child-1'), isNotNull);
    expect(await filed(io, PqSigningChain.linkField), isNull,
        reason: 'once stamped, the atServer holds it');
  });

  test('a filed link for another enrollment is dropped without being stamped',
      () async {
    final parentClient = client('parent-1');
    final parent = await registered(parentClient);
    await registered(client('other-1'));
    final childClient = client('child-1');
    await registered(childClient);
    final io = await keyfileFor(childClient, 'child-1');
    final elsewhere =
        await PqSigningChain(parentClient).signLinkFor(parent, 'other-1');
    await PqSigningChain(childClient)
        .fileConveyedLink(chainLinkSecret(elsewhere!));
    expect(await filed(io, PqSigningChain.linkField), isNotNull,
        reason: 'the premise: the link is filed');

    expect(await PqSigningChain(childClient).publishPendingLink(), isFalse);

    expect(await PqSigningChain(childClient).readLink('child-1'), isNull);
    expect(await filed(io, PqSigningChain.linkField), isNull,
        reason: 'it can never be stamped here, so keeping it would only '
            'retry it at every start');
  });

  test('a filed link that cannot be stamped yet stays filed until it can be',
      () async {
    final signed = await signedChainLink();
    final io = await keyfileFor(signed.child, 'child-1');
    await PqSigningChain(signed.child)
        .fileConveyedLink(chainLinkSecret(signed.link));
    final uri = PqSigningChain.apskUri(atSign, 'child-1');
    final record = remoteData.remove(uri)!;

    expect(await PqSigningChain(signed.child).publishPendingLink(), isFalse);
    expect(await filed(io, PqSigningChain.linkField), isNotNull,
        reason: 'an _apsk that cannot be read now may be readable at the '
            'next start');

    remoteData[uri] = record;
    expect(await PqSigningChain(signed.child).publishPendingLink(), isTrue);
    expect(await filed(io, PqSigningChain.linkField), isNull);
  });

  test(
      'with no keyfile entry for the enrollment, a link is held in memory '
      'and still stamped', () async {
    final signed = await signedChainLink();
    final io = await keyfileFor(signed.child, 'child-1', withEntry: false);
    final secret = chainLinkSecret(signed.link);
    await AtClientSecretSharing.forClient(signed.child)
        .secretStore
        .putSecret(secret, allowReservedName: true);

    expect(await PqSigningChain(signed.child).fileConveyedLink(secret), isFalse,
        reason: 'filing an entry here would turn a legacy keyfile typed');
    expect((await io.read(atSign)).enrollmentIds, isEmpty);

    expect(await PqSigningChain(signed.child).publishPendingLink(), isTrue);
  });

  test('a filed root link is stamped after a restart, then dropped', () async {
    final pair = await MlDsa65PureDartAlgo().generateKeyPair();
    remoteData['public:${PqSigningRoot.recordName}$atSign'] =
        jsonEncode(apskAdvertisement(keys: [
      ApskSigningKey.forPublicKey(
          alg: PqSigningRoot.rootKeyAlgo, pub: base64Encode(pair.publicKey))
    ]));
    final holderClient = client('holder-1');
    await registered(holderClient);
    final childClient = client('child-1');
    await registered(childClient);
    final link = await PqSigningChain(holderClient)
        .signRootLinkFor('child-1', rootPrivate: pair.secretKey);
    final io = await keyfileFor(childClient, 'child-1');
    await PqSigningChain(childClient).fileConveyedLink(Secret(
        namespace: 'buzz',
        name: PqSigningChain.rootLinkSecretName,
        value: PqSigningChain.encodeLink(link!)));
    expect(await filed(io, PqSigningChain.rootLinkField), isNotNull,
        reason: 'the premise: the link is filed');

    final after = restarted('child-1', io);
    expect(await PqSigningChain(after).publishPendingLink(), isTrue);

    expect(await PqSigningChain(after).readRootLink('child-1'), isNotNull);
    expect(await filed(io, PqSigningChain.rootLinkField), isNull);
  });

  group('a link arriving at a running client', () {
    test('is filed and stamped as it arrives', () async {
      final signed = await signedChainLink();
      final io = await keyfileFor(signed.child, 'child-1');
      PqClientBootstrap(signed.child,
          keysIo: io,
          privilege: _Unprivileged(),
          sweepUnanchoredEnrollments: () async => 0);

      await AtClientSecretSharing.forClient(signed.child)
          .fileReceivedSecret!(chainLinkSecret(signed.link));

      expect(await PqSigningChain(signed.child).readLink('child-1'), isNotNull,
          reason: 'a long-running client would otherwise hold it unstamped '
              'until it restarted');
      expect(await filed(io, PqSigningChain.linkField), isNull);
    });

    test('is left alone when the start-up does not publish links', () async {
      final signed = await signedChainLink();
      final io = await keyfileFor(signed.child, 'child-1');
      PqClientBootstrap(signed.child,
          keysIo: io,
          privilege: _Unprivileged(),
          sweepUnanchoredEnrollments: () async => 0,
          gates: const PqStartupGates(publishChainLink: false));

      await AtClientSecretSharing.forClient(signed.child)
          .fileReceivedSecret!(chainLinkSecret(signed.link));

      expect(await PqSigningChain(signed.child).readLink('child-1'), isNull);
      expect(await filed(io, PqSigningChain.linkField), isNull);
    });
  });
}
