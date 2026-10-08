// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart' show ApskSigningKey, apskAdvertisement;
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

/// A link conveyed to an enrollment is stamped as it arrives, and the envelope
/// carrying it is kept while it could still be stamped later.
///
/// The arrival hook's throw is what keeps an envelope: the sweep deletes one
/// only after the hook returns.
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

  /// [c]'s arrival hook, wired as a client start wires it.
  Future<Future<void> Function(Secret)> hookOf(MockAtClient c,
      {PqStartupGates gates = const PqStartupGates()}) async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys(atsign: atSign.toAtsign()));
    when(() => c.atKeysIo).thenReturn(io);
    PqClientBootstrap(c,
        keysIo: io,
        privilege: _Unprivileged(),
        sweepUnanchoredEnrollments: () async => 0,
        gates: gates);
    return AtClientSecretSharing.forClient(c).fileReceivedSecret!;
  }

  Secret chainLinkSecret(Map<String, Object?> link) => Secret(
      namespace: 'buzz',
      name: PqSigningChain.linkSecretName,
      value: PqSigningChain.encodeLink(link));

  Secret rootLinkSecret(Map<String, Object?> link) => Secret(
      namespace: 'buzz',
      name: PqSigningChain.rootLinkSecretName,
      value: PqSigningChain.encodeLink(link));

  /// A chain link for `child-1`, signed by `parent-1`, with both registered.
  Future<({MockAtClient child, Map<String, Object?> link})>
      signedChainLink() async {
    final parentClient = client('parent-1');
    final parent = await registered(parentClient);
    final childClient = client('child-1');
    await registered(childClient);
    final link =
        await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
    return (child: childClient, link: link!.toJson());
  }

  /// A root link for `child-1`, under a signing root the atServer publishes.
  Future<({MockAtClient child, Map<String, Object?> link})>
      signedRootLink() async {
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
    return (child: childClient, link: link!);
  }

  test('a chain link is stamped as it arrives', () async {
    final signed = await signedChainLink();
    final hook = await hookOf(signed.child);

    await hook(chainLinkSecret(signed.link));

    expect(await PqSigningChain(signed.child).readLink('child-1'), isNotNull,
        reason: 'a long-running client would otherwise hold it unstamped '
            'until it restarted');
  });

  test('a root link is stamped as it arrives', () async {
    final signed = await signedRootLink();
    final hook = await hookOf(signed.child);

    await hook(rootLinkSecret(signed.link));

    expect(
        await PqSigningChain(signed.child).readRootLink('child-1'), isNotNull);
  });

  test(
      'a link that cannot be stamped yet keeps its envelope, and is stamped '
      'when it can be', () async {
    final signed = await signedChainLink();
    final hook = await hookOf(signed.child);
    final uri = PqSigningChain.apskUri(atSign, 'child-1');
    final record = remoteData.remove(uri)!;

    await expectLater(hook(chainLinkSecret(signed.link)), throwsException,
        reason: 'an _apsk that cannot be read now may be readable at the next '
            'start, and the throw is what keeps the envelope until then');
    expect(await PqSigningChain(signed.child).readLink('child-1'), isNull);

    remoteData[uri] = record;
    await hook(chainLinkSecret(signed.link));
    expect(await PqSigningChain(signed.child).readLink('child-1'), isNotNull);
  });

  test('a chain link whose signer cannot be checked now keeps its envelope',
      () async {
    final signed = await signedChainLink();
    final hook = await hookOf(signed.child);
    final parentUri = PqSigningChain.apskUri(atSign, 'parent-1');
    when(() => signed.child
            .get(any(), getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments[0].toString();
      if (key == parentUri) throw Exception('the atServer did not answer');
      final value = remoteData[key];
      if (value == null) throw AtKeyNotFoundException(key);
      return AtValue()
        ..value = value
        ..metadata = remoteMetadata[key];
    });

    await expectLater(hook(chainLinkSecret(signed.link)), throwsException,
        reason: 'a failure to reach the signer says nothing about the link, so '
            'it is tried again rather than given up');
    expect(await PqSigningChain(signed.child).readLink('child-1'), isNull);
  });

  test('a link for another enrollment lets its envelope go unstamped',
      () async {
    final parentClient = client('parent-1');
    final parent = await registered(parentClient);
    await registered(client('other-1'));
    final childClient = client('child-1');
    await registered(childClient);
    final elsewhere =
        await PqSigningChain(parentClient).signLinkFor(parent, 'other-1');
    final hook = await hookOf(childClient);

    await hook(chainLinkSecret(elsewhere!.toJson()));

    expect(await PqSigningChain(childClient).readLink('child-1'), isNull,
        reason: 'it can never be stamped here, so keeping its envelope would '
            'only retry it at every start');
  });

  test('a chain link whose signature does not verify lets its envelope go',
      () async {
    final signed = await signedChainLink();
    final hook = await hookOf(signed.child);
    final tampered =
        jsonDecode(jsonEncode(signed.link)) as Map<String, dynamic>;
    final entry = (tampered['signatures'] as List).first as Map;
    final signature = entry['signature'] as String;
    entry['signature'] =
        (signature.startsWith('A') ? 'B' : 'A') + signature.substring(1);

    await hook(chainLinkSecret(tampered));

    expect(await PqSigningChain(signed.child).readLink('child-1'), isNull,
        reason: 'a signature that does not verify never will');
  });

  test('a chain link whose signer\'s _apsk is gone lets its envelope go',
      () async {
    final signed = await signedChainLink();
    final hook = await hookOf(signed.child);
    remoteData.remove(PqSigningChain.apskUri(atSign, 'parent-1'));

    await hook(chainLinkSecret(signed.link));

    expect(await PqSigningChain(signed.child).readLink('child-1'), isNull,
        reason: 'the atServer says the signer publishes no key, so nothing '
            'can verify the link');
  });

  test('a root link with no signature lets its envelope go', () async {
    final signed = await signedRootLink();
    final hook = await hookOf(signed.child);

    await hook(rootLinkSecret({...signed.link, 'signature': 42}));

    expect(await PqSigningChain(signed.child).readRootLink('child-1'), isNull);
  });

  test('a root link with no payload lets its envelope go', () async {
    final signed = await signedRootLink();
    final hook = await hookOf(signed.child);

    await hook(rootLinkSecret({...signed.link, 'payload': 'child-1'}));

    expect(await PqSigningChain(signed.child).readRootLink('child-1'), isNull);
  });

  test('a link is left alone when the start-up does not publish links',
      () async {
    final signed = await signedChainLink();
    final hook = await hookOf(signed.child,
        gates: const PqStartupGates(publishChainLink: false));

    await hook(chainLinkSecret(signed.link));

    expect(await PqSigningChain(signed.child).readLink('child-1'), isNull);
  });

  test('the start-up stamps a link the secret store holds', () async {
    final signed = await signedChainLink();
    await AtClientSecretSharing.forClient(signed.child)
        .secretStore
        .putSecret(chainLinkSecret(signed.link), allowReservedName: true);

    expect(await PqSigningChain(signed.child).publishPendingLink(), isTrue);
    expect(await PqSigningChain(signed.child).readLink('child-1'), isNotNull);
  });
}
