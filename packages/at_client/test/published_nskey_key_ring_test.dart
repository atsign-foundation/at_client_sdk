import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Discovery of another atSign's advertised nskey.
///
/// A sender never sees a recipient's decapsulation fail, so re-fetching the
/// advertisement is the only way it learns of a rotation. That makes the
/// freshness policy a security property rather than a caching detail: a sender
/// still sealing to a superseded generation hands a revoked enrollment a key it
/// can still open.
void main() {
  const alice = '@alice';
  const bob = '@bob';
  const namespace = 'app_1.my_apps';

  late XWingKeyPair bobKey;

  setUpAll(() async {
    bobKey = await XWingKeyPair.generate();
    registerFallbackValue(AtKey());
  });

  String payloadFor(XWingKeyPair pair) => jsonEncode({
        'nskeyKid': nskeyKidOf(pair.publicKeyBytes),
        'publicKey': base64Encode(pair.publicKeyBytes),
      });

  /// A client whose advertisement fetch succeeds [succeedFor] times and throws
  /// afterwards — the shape of an atServer that goes unreachable.
  ({MockAtClient atClient, List<int> fetches}) client({int succeedFor = 999}) {
    final fetches = <int>[];
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    when(() => atClient.get(any())).thenAnswer((_) async {
      fetches.add(1);
      if (fetches.length > succeedFor) {
        throw SecondaryConnectException('atServer unreachable');
      }
      return AtValue()..value = payloadFor(bobKey);
    });
    return (atClient: atClient, fetches: fetches);
  }

  test('a fetched advertisement is reused inside the TTL', () async {
    final c = client();
    final ring = PublishedNskeyKeyRing(c.atClient,
        advertisementTtl: const Duration(minutes: 15));

    await ring.currentPublic(bob, namespace);
    await ring.currentPublic(bob, namespace);

    expect(c.fetches, hasLength(1),
        reason: 'a round trip to the recipient atServer on every put would '
            'break offline writes — the TTL is the trade');
  });

  test('the advertisement is re-fetched once the TTL has passed', () async {
    final c = client();
    final ring = PublishedNskeyKeyRing(c.atClient,
        advertisementTtl: const Duration(milliseconds: 1));

    await ring.currentPublic(bob, namespace);
    await Future.delayed(const Duration(milliseconds: 20));
    await ring.currentPublic(bob, namespace);

    expect(c.fetches, hasLength(2),
        reason: 're-fetching is the only way a sender learns of a rotation');
  });

  test('a failed re-fetch keeps serving the known key inside the grace',
      () async {
    final c = client(succeedFor: 1);
    final ring = PublishedNskeyKeyRing(c.atClient,
        advertisementTtl: const Duration(milliseconds: 1),
        advertisementStaleGrace: const Duration(minutes: 15));

    final first = await ring.currentPublic(bob, namespace);
    await Future.delayed(const Duration(milliseconds: 20));
    final second = await ring.currentPublic(bob, namespace);

    expect(second?.nskeyKid, first?.nskeyKid,
        reason: 'an ordinary blip must not cost a working key');
  });

  test('a failed re-fetch stops serving the known key past the grace',
      () async {
    final c = client(succeedFor: 1);
    final ring = PublishedNskeyKeyRing(c.atClient,
        advertisementTtl: const Duration(milliseconds: 1),
        advertisementStaleGrace: const Duration(milliseconds: 1));

    expect(await ring.currentPublic(bob, namespace), isNotNull);
    await Future.delayed(const Duration(milliseconds: 30));

    expect(await ring.currentPublic(bob, namespace), isNull,
        reason: 'serving a stale generation indefinitely makes the stated '
            '"TTL plus one content key" exposure unbounded — and a peer that '
            'rotated because of a revocation is the one to stop sealing to');
  });

  test('an atSign that has never published resolves to nothing', () async {
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    when(() => atClient.get(any()))
        .thenThrow(KeyNotFoundException('no such key'));

    expect(await PublishedNskeyKeyRing(atClient).currentPublic(bob, namespace),
        isNull,
        reason: 'that is the cold-start case, which belongs to the provider');
  });

  test('the ring answers for its own atSign from what it minted', () async {
    final c = client();
    final ring = PublishedNskeyKeyRing(c.atClient);

    expect(await ring.currentPublic(alice, namespace), isNull,
        reason: 'nothing minted yet');
    expect(c.fetches, isEmpty,
        reason: 'the owner never looks up her own advertisement');
  });
}
