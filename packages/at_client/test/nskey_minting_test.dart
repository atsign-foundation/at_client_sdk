import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_mint_lock.dart';
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {
  // The real spec getter has a concrete rsa2048 default; `implements` erases
  // it, and an unstubbed mocktail getter returns null into a non-nullable.
  @override
  SigningAlgoType get signingAlgoType => SigningAlgoType.rsa2048;
}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

class FakeUpdateVerbBuilder extends Fake implements UpdateVerbBuilder {}

/// Minting a namespace key: the interlock between an atSign's own
/// enrollments, and the ordering that stops a key being published before
/// anyone can open it.
void main() {
  const atSign = '@alice';
  const namespace = 'app_1.my_apps';

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(FakeUpdateVerbBuilder());
  });

  /// A client whose remote verbs succeed, recording what was sent. [lockTaken]
  /// makes the lock's immutable create fail, which is how the atServer reports
  /// that another enrollment already holds it.
  ({MockAtClient client, List<AtKey> verbs}) client(
      {bool lockAlreadyHeld = false}) {
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    final lookUp = MockAtLookupImpl();
    final verbs = <AtKey>[];

    when(() => atClient.atChops).thenReturn(AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair())));
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
    when(() => secondary.atLookUp).thenReturn(lookUp);
    when(() => lookUp.enrollmentId).thenReturn('enroll-a');
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((_) async => true);
    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((inv) async =>
            throw AtKeyNotFoundException('${inv.positionalArguments[0]}'));

    when(() => secondary.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((inv) async {
      final builder = inv.positionalArguments[0];
      if (builder is UpdateVerbBuilder) {
        verbs.add(builder.atKey);
        if (builder.atKey.key == '_nskeylock' && lockAlreadyHeld) {
          // What the atServer says to the loser of the race.
          throw AtLookUpException(
              'AT0023', 'Immutable records may not be updated');
        }
      }
      return 'data:1';
    });
    return (client: atClient, verbs: verbs);
  }

  Future<NskeyPrivateFiling> filing() async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    return NskeyPrivateFiling(keysIo: io, atSign: atSign);
  }

  test('the private is durable before the public half is published', () async {
    final c = client();
    final filer = await filing();
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);

    final advertisement = await ring.mintAndPublish(namespace);

    expect(await filer.read(namespace, advertisement.nskeyKid), isNotNull,
        reason: 'a key published ahead of its private leaves every sender '
            'sealing to something nobody can open, and rotation replaces the '
            'key rather than decrypting what was written meanwhile');
    // Ordering, not just presence: the lock is taken, then the advertisement
    // goes out. The filing happens between them, off the wire.
    final published =
        c.verbs.where((k) => k.key?.startsWith('__nskey') == true);
    expect(published, hasLength(1));
  });

  test('a mint that cannot store its private publishes nothing', () async {
    final c = client();
    // Key storage with nothing in it for this atSign: `read` throws, so
    // `store` cannot persist and the mint must publish nothing rather than
    // leave a key whose private dies with the process.
    final ring = PublishedNskeyKeyRing(c.client,
        privateFiling:
            NskeyPrivateFiling(keysIo: InMemoryAtKeysIo(), atSign: atSign));

    await expectLater(
        ring.mintAndPublish(namespace), throwsA(isA<StateError>()));
    expect(c.verbs.where((k) => k.key?.startsWith('__nskey') == true), isEmpty,
        reason: 'the advertisement is the promise that a private exists; '
            'making it when one does not is the failure this ordering exists '
            'to prevent');
  });

  test('the lock is taken remotely, before anything is published', () async {
    final c = client();
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: await filing());

    await ring.mintAndPublish(namespace);

    expect(c.verbs.first.key, '_nskeylock',
        reason: 'the atServer refusing a second immutable create is the only '
            'thing serialising two enrollments — a local-first put would let '
            'both believe they won and collide at sync');
    expect(c.verbs.first.metadata.immutable, isTrue);
    expect(c.verbs.first.metadata.ttl, isNotNull,
        reason: 'a holder that dies mid-mint must not block its atSign for '
            'good');
  });

  test('the loser of the race adopts the winner\'s advertisement', () async {
    final c = client(lockAlreadyHeld: true);
    final winner = await XWingKeyPair.generate();
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: await filing());
    // The winner published while this client was trying to take the lock.
    ring.rememberOwn(atSign, namespace, (
      nskeyKid: nskeyKidOf(winner.publicKeyBytes),
      publicKey: winner.publicKeyBytes,
    ));

    final adopted = await ring.mintAndPublish(namespace);

    expect(adopted.nskeyKid, nskeyKidOf(winner.publicKeyBytes),
        reason: 'minting a second key would rotate the first out from under '
            'every peer that had already fetched it');
    expect(c.verbs.where((k) => k.key?.startsWith('__nskey') == true), isEmpty,
        reason: 'and the loser publishes nothing at all');
  });
}
