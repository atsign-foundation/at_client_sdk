/// B5 · Retrofit edge cases.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 12.
library;

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';
import 'blockers.dart';
import 'proven_elsewhere.dart';

void main() {
  group('B5 · retrofit edge cases', () {
    test('UC-B5.1 · offline enrollment pulls the signing root later', () {
      // GIVEN alice2 was offline during the retrofit wave; pq_signing_root was
      //       created by alice1.
      // WHEN  alice2 next comes online and retrofits.
      // THEN  pq_signing_root has no namespace, so it has NO enroll:listns
      //       push — its requestSecret is the steady-state path, answered by any
      //       online holder and persisting until one answers. Namespaced nskey
      //       privates missed during the offline window arrive by the PUSH
      //       primary path once a holder is online, with requestSecret as the
      //       backstop.
      //
      // The row splits. Namespaced nskey privates DO arrive by the push path
      // (NskeySeeding's conveyance). The headline half — requestSecret as the
      // steady-state route to the root — had no initiator at all until
      // PqSigningRoot.requestPrivateIfAbsent was built and wired into client
      // start; its guards are unit-covered.
      //
      // What is still missing is the live round trip, and it needs a fixture
      // with two real APKAM enrollments. The functional harness authenticates
      // with the atSign's own keys, so the enumeration is refused outright
      // ("enroll:listns requires APKAM authentication"), and addressing a
      // holder directly lands the envelope but yields no answer — for reasons
      // not yet established and not guessed at. See decisions 30 and 31.
      //
      // This matters more than a missing convenience path: the root is
      // atSign-level and carries no namespace, so it is excluded from the
      // enroll:listns fan-out by construction. An enrollment that missed the
      // approval-time conveyance has no other route to it.
      fail('not implemented');
    }, skip: rootPullNotBuilt);

    test('UC-B5.2 · reading legacy history after retrofit', () async {
      // GIVEN alice1 retrofitted; the old legacy enrollment aged out; the legacy
      //       ENCRYPTION key is retained.
      // WHEN  alice1 reads pre-PQ data.
      // THEN  it decrypts via the legacy provider (reads are universal) and
      //       providerId routes per value. PQ retrofit NEVER makes old data
      //       unreadable.
      //
      // The claim that matters here, and the one the cross-cutting
      // "reads are universal" row does NOT make, is that routing is decided
      // **per value** rather than per client or per namespace. After a retrofit
      // a single namespace holds both eras at once — everything written before
      // it and everything written after — so a client that picked one scheme
      // for the namespace would be wrong about half of it.
      const namespace = 'app_1.my_apps';
      final legacy = _RecordingProvider(legacyCryptoProviderId);
      final pq = _RecordingProvider(symmetricAesGcmCryptoProviderId);

      final client = MockAtClient();
      // The retrofitted client: writes the PQ scheme by default, and has NOT
      // dropped the legacy provider — that retention is what "the legacy
      // ENCRYPTION key is retained" means in config terms.
      client.getPreferences().crypto = CryptoConfig(
          defaultProviderId: symmetricAesGcmCryptoProviderId,
          providers: [legacy, pq]);
      final runtime = CryptoRuntime(client);

      AtKey record(String name, String providerId) => AtKey()
        ..key = name
        ..namespace = namespace
        ..sharedBy = '@alice'
        ..metadata =
            (Metadata()..appMetadata = AppMetadata(providerId: providerId));

      // Two records, same atSign, same namespace, different eras.
      expect(
          await runtime.decryptForGet(
              record('written_in_2024', legacyCryptoProviderId), 'old'),
          '$legacyCryptoProviderId decrypted old');
      expect(
          await runtime.decryptForGet(
              record('written_today', symmetricAesGcmCryptoProviderId), 'new'),
          '$symmetricAesGcmCryptoProviderId decrypted new');

      expect(legacy.decryptCalls, 1,
          reason: 'the pre-retrofit record must reach the legacy provider — if '
              'it reached the PQ one, retrofitting made old data unreadable, '
              'which is the single thing this row exists to forbid');
      expect(pq.decryptCalls, 1,
          reason: 'and the post-retrofit record must reach the PQ one, or the '
              'routing is not per-value at all and one of these two passed by '
              'accident');

      // And a NEW write in that same namespace still goes out PQ: retaining
      // the ability to read the old era must not drag the write default back.
      //
      // Asked of `providerIdFor`, which is where the write scheme is actually
      // decided. `encryptForPut` routes by the id already stamped on the key,
      // so asking IT which scheme a new write gets would answer "legacy" for
      // every unstamped key and prove nothing.
      final fresh = AtKey()
        ..key = 'written_next'
        ..namespace = namespace
        ..sharedBy = '@alice'
        ..metadata = Metadata();
      expect(CryptoRuntime.providerIdFor(client, null, atKey: fresh),
          symmetricAesGcmCryptoProviderId,
          reason: 'reads stay universal; writes move forward');
    });

    test('UC-B5.3 · two enrollments race to create the signing root', () {
      // GIVEN alice1 and alice3 both reach the create step with pq_signing_root
      //       absent.
      // WHEN  both attempt the immutable create.
      // THEN  exactly one wins; the other gets "already exists" and falls
      //       through to REQUEST. No orphaned data (readiness not yet flipped).
      provenIn(
        'tests/at_functional_test/test/pq_signing_root_create_once_test.dart',
        'the enrollment that loses the create does not mint a second root',
        proves: 'the loser returns null rather than publishing or retrying, '
            'leaves the published record untouched, and a namespace-scoped '
            'enrollment declines to attempt the mint at all',
      );
    });
  });
}

/// Names itself in its output, so a routing assertion cannot pass by reaching
/// the wrong provider and getting a plausible-looking string back.
class _RecordingProvider implements CryptoProvider {
  @override
  final String id;

  int decryptCalls = 0;

  _RecordingProvider(this.id);

  @override
  Future<String> encrypt(
          CryptoContext context, AtKey atKey, String plaintext) async =>
      '$id encrypted $plaintext';

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String ciphertext) async {
    decryptCalls++;
    return '$id decrypted $ciphertext';
  }
}
