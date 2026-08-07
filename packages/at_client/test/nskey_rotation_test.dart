import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show signedEnvelopeVersion;
import 'package:at_client/src/secret_sharing/secret_store.dart';
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

class MockEnrollmentService extends Mock implements EnrollmentService {}

class MockSharing extends Mock implements PairwiseSecretSharing {}

class FakeUpdateVerbBuilder extends Fake implements UpdateVerbBuilder {}

class FakeSecret extends Fake implements Secret {}

class FakeEnrollmentRequestDecision extends Fake
    implements EnrollmentRequestDecision {}

/// The nskey-keypair rotation lever (design.md §1.7 B5b) and the revocation it
/// composes with (B6).
void main() {
  const atSign = '@alice';
  const namespace = 'app_1.my_apps';

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(FakeUpdateVerbBuilder());
    registerFallbackValue(FakeSecret());
    registerFallbackValue(FakeEnrollmentRequestDecision());
  });

  /// A client whose remote verbs succeed, recording an ordered trace of what
  /// it was asked to do. [lockAlreadyHeld] makes the mint lock's immutable
  /// create fail, which is how the atServer reports that another enrollment
  /// holds it.
  ({MockAtClient client, List<String> trace, List<String> published}) client(
      {bool lockAlreadyHeld = false}) {
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    final lookUp = MockAtLookupImpl();
    final trace = <String>[];
    final published = <String>[];

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
        final key = builder.atKey.key;
        if (key == '_nskeylock') {
          if (lockAlreadyHeld) {
            // What the atServer says to the loser of the race.
            throw AtLookUpException(
                'AT0023', 'Immutable records may not be updated');
          }
        } else if (key.startsWith('__nskey')) {
          trace.add('publish:${builder.atKey.namespace}');
          published.add(builder.value as String);
        }
      }
      return 'data:1';
    });
    return (client: atClient, trace: trace, published: published);
  }

  Future<NskeyPrivateFiling> filing() async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    return NskeyPrivateFiling(keysIo: io, atSign: atSign);
  }

  /// A sharing substrate that records what it was asked to push and to whom.
  ({MockSharing sharing, List<(Secret, Set<String>)> pushes}) sharing() {
    final mock = MockSharing();
    final pushes = <(Secret, Set<String>)>[];
    when(() => mock.pushSecretToNamespaceMembers(any(),
            excludeEnrollmentIds: any(named: 'excludeEnrollmentIds')))
        .thenAnswer((inv) async {
      pushes.add((
        inv.positionalArguments[0] as Secret,
        inv.namedArguments[#excludeEnrollmentIds] as Set<String>,
      ));
      return 2;
    });
    return (sharing: mock, pushes: pushes);
  }

  /// Puts [ring] into the "already published" state without a live atServer,
  /// and returns the generation it now serves.
  NskeyAdvertisement published(PublishedNskeyKeyRing ring, Uint8List seed) {
    final advertisement = (
      nskeyKid: nskeyKidOf(seed),
      publicKey: seed,
      alg: SecretSharingAlgos.xWing
    );
    ring.rememberOwn(atSign, namespace, advertisement);
    return advertisement;
  }

  final generation0 =
      Uint8List.fromList(List<int>.generate(32, (i) => 200 - i));

  group('the rotation lever', () {
    test('the published advertisement carries a payload version', () async {
      // The reader accepts a payload with no `v` as the pre-2026-08-06 shape,
      // so nothing would notice the writer dropping it — which is precisely
      // why the writer needs its own assertion rather than a round trip.
      final c = client();
      final ring =
          PublishedNskeyKeyRing(c.client, privateFiling: await filing());

      await ring.mintAndPublish(namespace);

      expect(c.published, hasLength(1));
      final envelope = jsonDecode(c.published.single) as Map<String, dynamic>;
      expect((envelope['payload'] as Map)['v'], nskeyAdvertisementVersion);
      expect(envelope['v'], signedEnvelopeVersion);
    });

    test('publishes a fresh generation and keeps the superseded private',
        () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);

      // A first generation this client actually holds the private for, so the
      // retention claim is about a key it could otherwise have dropped.
      final first = await ring.mintAndPublish(namespace);
      final second = await ring.rotate(namespace);

      expect(second.nskeyKid, isNot(first.nskeyKid));
      expect(await filer.read(namespace, second.nskeyKid), isNotNull);
      expect(await filer.read(namespace, first.nskeyKid), isNotNull,
          reason: 'retained __ck records sealed to the superseded generation '
              'still have to open — rotation replaces the key, it does not '
              'decrypt or re-encrypt the past');
      expect(
          await ring.currentPublic(atSign, namespace),
          isA<NskeyAdvertisement>()
              .having((a) => a.nskeyKid, 'nskeyKid', second.nskeyKid),
          reason: 'and new writes must seal to the successor');
    });

    test('a rotation that loses the mint lock fails instead of adopting',
        () async {
      final c = client(lockAlreadyHeld: true);
      final ring =
          PublishedNskeyKeyRing(c.client, privateFiling: await filing());
      final current = published(ring, generation0);

      await expectLater(ring.rotate(namespace), throwsA(isA<StateError>()),
          reason: 'a cold-start mint that loses the race adopts the winner and '
              'is done; a rotation that adopts what it finds has rotated '
              'nothing while reporting success, leaving the enrollment it was '
              'excluding holding the live generation');
      // The contrast that makes the point: the same loss on the mint path is a
      // resolution, not a failure.
      expect((await ring.mintAndPublish(namespace)).nskeyKid, current.nskeyKid);
      expect(c.trace, isEmpty, reason: 'and the loser publishes nothing');
    });

    test('rotating a namespace with no published key is refused', () async {
      final c = client();
      final ring =
          PublishedNskeyKeyRing(c.client, privateFiling: await filing());

      await expectLater(ring.rotate(namespace), throwsA(isA<StateError>()),
          reason: 'that is a cold-start mint wearing a rotation\'s name, and a '
              'caller that meant to supersede a generation should hear there '
              'was none');
      expect(c.trace, isEmpty);
    });
  });

  group('rotation-time conveyance', () {
    test('pushes the successor private to the namespace members', () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      final s = sharing();
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      final outcome = await rotation.rotateNamespaceKey(namespace);

      expect(s.pushes, hasLength(1));
      final (secret, excluded) = s.pushes.single;
      expect(secret.namespace, namespace);
      expect(secret.name,
          '${NskeyPrivateFiling.secretNamePrefix}${outcome.advertisement.nskeyKid}');
      expect(base64Decode(secret.value),
          await filer.read(namespace, outcome.advertisement.nskeyKid),
          reason: 'what the other enrollments receive must be exactly what '
              'this client will itself use — the durable copy, not a value '
              'held only in the mint call');
      expect(excluded, isEmpty);
      expect(outcome.conveyedTo, 2);
      expect(outcome.supersededKid, isNot(outcome.advertisement.nskeyKid));
    });

    test('does not push to an excluded enrollment', () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      final s = sharing();
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      final outcome = await rotation
          .rotateNamespaceKey(namespace, excludeEnrollmentIds: {'enroll-b'});

      expect(s.pushes.single.$2, {'enroll-b'},
          reason: 'the exclusion has to reach the roster query, not merely be '
              'remembered by the caller');
      expect(outcome.excluded, {'enroll-b'});
    });

    test('a successor that cannot be read back is not conveyed', () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      final s = sharing();
      // A rotation whose ring files the private, paired with a filing that
      // cannot read it back: what the substrate would carry is unknown, so it
      // must carry nothing.
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling:
              NskeyPrivateFiling(keysIo: InMemoryAtKeysIo(), atSign: atSign),
          sharing: s.sharing);

      await expectLater(
          rotation.rotateNamespaceKey(namespace), throwsA(isA<StateError>()));
      expect(s.pushes, isEmpty);
    });
  });

  test('a client with no key storage is refused a rotation', () async {
    final c = client();
    when(() => c.client.atKeysIo).thenReturn(null);

    expect(() => NskeyRotation.forClient(c.client), throwsA(isA<StateError>()),
        reason: 'the successor private would live only in memory and die with '
            'the process, leaving every peer sealing to a generation this '
            'atSign can no longer open — strictly worse than not rotating');
  });

  group('the revocation composition', () {
    ({MockEnrollmentService service, List<String> order}) enrollmentService(
        MockAtClient atClient,
        {Map<String, dynamic>? grants,
        List<String>? order,
        Map<String, dynamic> callerGrants = const {
          '*': 'rw',
          '__manage': 'rw'
        }}) {
      final service = MockEnrollmentService();
      final trace = order ?? <String>[];
      when(() => atClient.enrollmentService).thenReturn(service);
      when(() => service.fetchEnrollmentRequests(
              enrollmentListParams: any(named: 'enrollmentListParams')))
          .thenAnswer((_) async => [
                // The caller's own record. The atServer always returns it, and
                // it is what says whether this client may revoke at all.
                Enrollment()
                  ..enrollmentId = 'enroll-a'
                  ..namespace = callerGrants,
                Enrollment()
                  ..enrollmentId = 'enroll-b'
                  ..namespace = grants ?? {namespace: 'rw'}
              ]);
      when(() => service.revoke(any())).thenAnswer((inv) async {
        trace.add(
            'revoke:${(inv.positionalArguments[0] as EnrollmentRequestDecision).enrollmentId}');
        return AtEnrollmentResponse('enroll-b', EnrollmentStatus.revoked);
      });
      return (service: service, order: trace);
    }

    test('revokes before it rotates', () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      c.trace.clear();
      final e = enrollmentService(c.client, order: c.trace);
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: sharing().sharing);

      await rotation.revokeEnrollmentAndRotate('enroll-b');

      expect(c.trace, ['revoke:enroll-b', 'publish:$namespace'],
          reason: 'the ordering IS the enforcement: revoking first drops the '
              'enrollment out of enroll:listns, so by the time the rotation '
              'runs it is refused at every serve — rotate first and it can '
              'simply pull the successor from another holder in the gap');
      expect(e.service, isNotNull);
    });

    test('rotates every granted namespace, excluding the revoked id', () async {
      const other = 'app_2.my_apps';
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      await ring.mintAndPublish(other);
      final s = sharing();
      enrollmentService(c.client,
          grants: {namespace: 'rw', other: 'r', '__manage': 'rw', '*': 'rw'});
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      final outcomes = await rotation.revokeEnrollmentAndRotate('enroll-b');

      expect(outcomes.map((o) => o.namespace).toSet(), {namespace, other},
          reason: 'a read grant still hands over every key the namespace '
              'protects, so "could read it" is the bar, not "could write it"');
      expect(s.pushes.map((p) => p.$2), everyElement({'enroll-b'}));
      expect(outcomes.map((o) => o.namespace), isNot(contains('__manage')),
          reason: 'enrollment administration is not an app namespace');
      expect(outcomes.map((o) => o.namespace), isNot(contains('*')),
          reason: 'a wildcard authorises every namespace and is not itself '
              'one — there is no public:__nskey.* to overwrite');
    });

    test('one namespace failing to rotate does not abandon the rest', () async {
      const unminted = 'app_3.my_apps';
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      final s = sharing();
      enrollmentService(c.client, grants: {unminted: 'rw', namespace: 'rw'});
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      final outcomes = await rotation.revokeEnrollmentAndRotate('enroll-b');

      expect(outcomes.map((o) => o.namespace), [namespace],
          reason: 'the revoke has already landed, so abandoning the remainder '
              'would leave the atSign with an enrollment cut off from the '
              'server but still holding every live namespace key it had');
    });

    test('an unknown enrollment revokes nothing and rotates nothing', () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      c.trace.clear();
      final s = sharing();
      enrollmentService(c.client, order: c.trace);
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      await expectLater(rotation.revokeEnrollmentAndRotate('enroll-ghost'),
          throwsA(isA<StateError>()));
      expect(c.trace, isEmpty);
      expect(s.pushes, isEmpty);
    });

    test('a caller without __manage is refused, and revokes nothing', () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      c.trace.clear();
      final s = sharing();
      enrollmentService(c.client,
          order: c.trace, callerGrants: {namespace: 'rw'});
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      await expectLater(rotation.revokeEnrollmentAndRotate('enroll-b'),
          throwsA(isA<StateError>()));
      expect(c.trace, isEmpty);
      expect(s.pushes, isEmpty,
          reason: 'the two halves ask for different privileges and only one is '
              'obvious: rotating needs rw on the namespace, revoking needs '
              '__manage. Without it the atServer also returns only this '
              'client\'s OWN enrollment record, so the failure would surface '
              'as "no enrollment <id> to revoke" and send the caller looking '
              'for a wrong id');
    });
  });
}
