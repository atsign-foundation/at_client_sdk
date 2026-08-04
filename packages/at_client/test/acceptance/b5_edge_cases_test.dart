/// B5 · Retrofit edge cases.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 12.
library;

import 'package:test/test.dart';

import 'blockers.dart';

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
      fail('not implemented');
    }, skip: owedFunctional);

    test('UC-B5.2 · reading legacy history after retrofit', () {
      // GIVEN alice1 retrofitted; the old legacy enrollment aged out; the legacy
      //       ENCRYPTION key is retained.
      // WHEN  alice1 reads pre-PQ data.
      // THEN  it decrypts via the legacy provider (reads are universal) and
      //       providerId routes per value. PQ retrofit NEVER makes old data
      //       unreadable.
      fail('not implemented');
    }, skip: owedUnit);

    test('UC-B5.3 · two enrollments race to create the signing root', () {
      // GIVEN alice1 and alice3 both reach the create step with pq_signing_root
      //       absent.
      // WHEN  both attempt the immutable create.
      // THEN  exactly one wins; the other gets "already exists" and falls
      //       through to REQUEST. No orphaned data (readiness not yet flipped).
      fail('not implemented');
    }, skip: owedFunctional);
  });
}
