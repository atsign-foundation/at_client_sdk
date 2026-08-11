/// Guards asserted against the SOURCE TREE rather than against behaviour.
///
/// These read library source and check what it contains. That is a legitimate
/// thing to want — some invariants are about which code path exists at all,
/// and no runtime assertion can see "nobody has hand-rolled a second one of
/// these" — but it fails for a different reason from everything else in this
/// directory. A rename breaks a grep while the behaviour is intact, and when
/// that grep lives inside an acceptance row, the suite reports that the
/// scenario failed. It did not; the guard's assumption about the source did.
///
/// So they live here, and this file is a guard rather than a scenario: its
/// tests are not burn-down rows and are declared as such in `manifest.dart`.
///
/// Catalogue: `docs/projects/pq/acceptance.md`.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'manifest.dart';

void main() {
  test('metadata reaches the wire through one serializer', () {
    // One serializer serves both the stored key and the notification frame.
    // The regression this guards was a SECOND, hand-rolled serializer that
    // fell behind the shared one, and the symptom was silent: appMetadata
    // stopped reaching the atServer, so every cross-atSign read fell back to
    // legacy for every provider with no error anywhere.
    //
    // The behavioural half — that appMetadata is on the wire and carries the
    // provider id — is asserted by the `appMetadata.providerId is
    // authoritative on keys and frames` row in `cross_cutting_test.dart`.
    // What cannot be asserted at runtime is the absence of a rival
    // serializer, which is the only reason this is a source-text check.
    final lib = Directory('${repoRoot().path}/packages/at_client/lib/src');
    for (final path in const [
      'service/sync_service_impl.dart',
      'service/notification_service_impl.dart',
    ]) {
      expect(File('${lib.path}/$path').readAsStringSync(),
          contains('toAtProtocolFragment'),
          reason: '$path must serialize metadata through the shared fragment '
              'builder; a private one beside it is how appMetadata silently '
              'stopped reaching the atServer once already');
    }
  });

  test('every test file here is declared as a scenario file or a guard', () {
    // The burn-down count used to be "every *_test.dart except
    // catalogue_test.dart", so any file added to this directory joined the
    // row count by existing — and the only way to add a guard without
    // inflating the number the README is pinned to was to not add one. Both
    // lists are declarations now, and this is what keeps them honest.
    expect(undeclaredTestFiles(), isEmpty,
        reason: 'a test file here is neither a declared scenario file nor a '
            'declared guard. Add it to scenarioFiles in manifest.dart if its '
            'tests are burn-down rows, or to guardFiles if they are not — and '
            'update the README count in the same change if it is a scenario '
            'file');
    expect(missingDeclaredFiles(), isEmpty,
        reason: 'manifest.dart declares a file that is not here — a deleted '
            'scenario file silently drops its rows from the count');
  });
}
