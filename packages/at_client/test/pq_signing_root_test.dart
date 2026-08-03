import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

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
      {bool createRefused = false}) {
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
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
}
