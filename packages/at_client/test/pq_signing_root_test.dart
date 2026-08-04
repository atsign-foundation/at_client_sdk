import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookUp extends Mock implements AtLookUp {}

class FakeUpdateVerbBuilder extends Fake implements UpdateVerbBuilder {}

/// The atSign's root of trust.
///
/// Every property here is about the same thing: the record is immutable and
/// the root never rotates, so a mistake at mint is permanent. There is no
/// second attempt, no rotation to recover with, and two roots would leave half
/// an atSign's enrollments chaining to one the other half rejects.
void main() {
  const atSign = '@alice';

  setUpAll(() {
    registerFallbackValue(FakeUpdateVerbBuilder());
  });

  ({MockAtClient client, List<UpdateVerbBuilder> published}) client(
      {bool createRefused = false, String? enrollmentId = 'enrollment-1'}) {
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    // The signing-root pull reads the enrollment id off the lookup to tell an
    // APKAM enrollment from a client using the atSign's own keys.
    final lookup = MockAtLookUp();
    when(() => secondary.atLookUp).thenReturn(lookup);
    when(() => lookup.enrollmentId).thenReturn(enrollmentId);
    final published = <UpdateVerbBuilder>[];
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
    when(() => secondary.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((inv) async {
      final builder = inv.positionalArguments[0] as UpdateVerbBuilder;
      published.add(builder);
      if (createRefused) {
        throw AtLookUpException(
            'AT0023', 'Immutable records may not be updated');
      }
      return 'data:1';
    });
    return (client: atClient, published: published);
  }

  Future<InMemoryAtKeysIo> keysIo() async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    return io;
  }

  test('a fully privileged enrollment mints it, private filed first', () async {
    final c = client();
    final io = await keysIo();

    final publicKey = await PqSigningRoot(c.client, keysIo: io)
        .mintIfAbsent(isFullyPrivileged: true);

    expect(publicKey, isNotNull);
    final filed = (await io.read(atSign))
        .getKey(PqSigningRoot.keyId, CryptographicKeyType.privateSigning);
    expect(filed, isNotNull,
        reason: 'the record is immutable and the root never rotates, so a '
            'published root whose private did not survive can never be '
            'replaced');
    expect(filed!.keyAlgorithmType, KeyAlgorithmType.mlDsa65);

    final record = c.published.single;
    expect(record.atKey.key, PqSigningRoot.recordName);
    expect(record.atKey.metadata.immutable, isTrue,
        reason: 'create-once is what guarantees exactly one root exists — two '
            'would be unrecoverable, not merely untidy');
    expect(record.atKey.metadata.isPublic, isTrue);
    expect(jsonDecode(record.value!)['keys'], hasLength(1));
  });

  test('a restricted enrollment mints nothing', () async {
    final c = client();
    final io = await keysIo();

    expect(
        await PqSigningRoot(c.client, keysIo: io)
            .mintIfAbsent(isFullyPrivileged: false),
        isNull);
    expect(c.published, isEmpty,
        reason: 'an enrollment restricted to one namespace has no business '
            'minting the key that vouches for every other enrollment');
    expect((await io.read(atSign)).keys, isEmpty);
  });

  test('a mint that cannot file its private publishes nothing', () async {
    final c = client();

    await expectLater(
        // Key storage with nothing written for this atSign: the read throws.
        PqSigningRoot(c.client, keysIo: InMemoryAtKeysIo())
            .mintIfAbsent(isFullyPrivileged: true),
        throwsA(isA<StateError>()));
    expect(c.published, isEmpty,
        reason: 'an immutable record cannot be retried with a different key, '
            'so publishing before the private is safe would burn the one '
            'chance this atSign gets');
  });

  test('losing the create is not an error', () async {
    final c = client(createRefused: true);
    final io = await keysIo();

    expect(
        await PqSigningRoot(c.client, keysIo: io)
            .mintIfAbsent(isFullyPrivileged: true),
        isNull,
        reason: 'the atServer refusing a second create IS the create-once '
            'guarantee working — this client waits to be given the root '
            'rather than treating it as a failure');
  });

  group('requesting the private when this enrollment has none', () {
    /// Records what was broadcast without doing any real sharing.
    _RecordingSharing sharing() => _RecordingSharing();

    test('a privileged enrollment that holds nothing asks the namespace',
        () async {
      final io = await keysIo();
      final broadcast = sharing();

      final asked = await PqSigningRoot(client().client, keysIo: io)
          .requestPrivateIfAbsent(
        isFullyPrivileged: () async => true,
        sharing: broadcast,
        namespace: 'buzz',
      );

      expect(asked, 2,
          reason: 'it must reach the holders in the namespace; '
              'the root carries no namespace of its own, so this broadcast is the '
              'only route left to an enrollment that missed the conveyance');
      expect(broadcast.requests, hasLength(1));
      expect(broadcast.requests.single.namespace, 'buzz');
      expect(broadcast.requests.single.names, [PqSigningRoot.secretName],
          reason: 'it asks for the root by name rather than pulling whatever '
              'holders happen to have');
    });

    test('an enrollment that already holds it asks nobody', () async {
      final io = await keysIo();
      final atClient = client().client;
      final root = PqSigningRoot(atClient, keysIo: io);
      await root.store(atSign, Uint8List.fromList(List<int>.filled(32, 3)));

      final broadcast = sharing();
      expect(
          await root.requestPrivateIfAbsent(
            isFullyPrivileged: () async => true,
            sharing: broadcast,
            namespace: 'buzz',
          ),
          0);
      expect(broadcast.requests, isEmpty,
          reason: 'this runs on every start; a client that broadcast each time '
              'regardless would put a fan-out on the wire per launch per '
              'device, asking for something it is already holding');
    });

    test('a restricted enrollment asks nobody', () async {
      final io = await keysIo();
      final broadcast = sharing();

      expect(
          await PqSigningRoot(client().client, keysIo: io)
              .requestPrivateIfAbsent(
            isFullyPrivileged: () async => false,
            sharing: broadcast,
            namespace: 'buzz',
          ),
          0);
      expect(broadcast.requests, isEmpty,
          reason: 'only a fully privileged enrollment may hold the key that '
              'vouches for every enrollment on the atSign. Asking would be '
              'refused anyway, and asking announces to every holder that '
              'something unentitled is looking for it');
    });

    test('a client authenticating with the atSign\'s own keys asks nobody',
        () async {
      final io = await keysIo();
      // No enrollment id on the lookup: the atSign itself, not an enrollment.
      final broadcast = _RecordingSharing();

      expect(
          await PqSigningRoot(client(enrollmentId: null).client, keysIo: io)
              .requestPrivateIfAbsent(
            isFullyPrivileged: () async => true,
            sharing: broadcast,
            namespace: 'buzz',
          ),
          0);
      expect(broadcast.requests, isEmpty,
          reason: 'such a client CANNOT ask — enumerating holders goes through '
              'enroll:listns, which the atServer refuses without APKAM '
              'authentication — and has no reason to: it is the atSign, so its '
              'route to a missing root is to mint one. Without this guard '
              'every legacy PKAM client broadcasts, is refused, and logs a '
              'warning on each start');
    });

    test('the privilege check is not consulted before the cheaper one',
        () async {
      final io = await keysIo();
      final atClient = client().client;
      final root = PqSigningRoot(atClient, keysIo: io);
      await root.store(atSign, Uint8List.fromList(List<int>.filled(32, 3)));

      var privilegeChecked = false;
      await root.requestPrivateIfAbsent(
        isFullyPrivileged: () async {
          privilegeChecked = true;
          return true;
        },
        sharing: sharing(),
        namespace: 'buzz',
      );

      expect(privilegeChecked, isFalse,
          reason: 'resolving privilege costs a round trip to the enrollment '
              'record. Holding the private already settles the question, and '
              'that is the case on essentially every start of every client');
    });
  });
}

/// Captures broadcasts instead of sending them, so the guards can be asserted
/// on what reached the wire rather than on a return value the method could
/// produce without doing anything.
class _RecordingSharing extends Fake implements PairwiseSecretSharing {
  final List<({String namespace, List<String>? names})> requests = [];

  @override
  Future<int> requestSecretsFromNamespace(
    String namespace, {
    List<String>? names,
    String? namePrefix,
    Set<String> excludeEnrollmentIds = const {},
  }) async {
    requests.add((namespace: namespace, names: names));
    return 2;
  }
}
