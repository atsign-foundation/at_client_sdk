// These gates read the filesystem to inspect sources, so they run on the VM
// only. Without this they would be compiled and launched by the T2
// node+dart2wasm platform run, where dart:io throws and the failure looks like a
// neutrality problem rather than a test that was never meant to run there.
@TestOn('vm')
library;

import 'package:test/test.dart'; // for the @TestOn annotation above
import 'package:wasm_shakedown/ratchet.dart';

/// Dependency-tree ratchet for `package:at_lookup/at_lookup.dart`.
///
/// Every offender below is the same problem seen from six places: `AtConnection`
/// exposes `Socket getSocket()`, so `dart:io` is in the package's public type
/// surface rather than tucked behind an implementation. The whole list comes off
/// together when the transport interface lands and the socket factories are
/// retyped — it does not shrink incrementally, and a baseline that starts
/// shrinking one file at a time is a sign someone is papering over the type
/// rather than replacing it.
///
/// Baseline taken 2026-08-13 against trunk `20f7f4da5`. Regenerate with
/// `dart run wasm_shakedown:baseline package:at_lookup/at_lookup.dart`.
void main() {
  ratchetGroup(
    'package:at_lookup/at_lookup.dart',
    package: 'at_lookup',
    expectedOffenders: const <String, List<String>>{
      // The three socket factories are already injectable; their SecureSocket
      // return type is the blocker.
      'lib/src/at_lookup_impl.dart': ['dart:io'],
      // Opens a raw TLS socket to the atDirectory. Needs a web implementation
      // through either the abstract finder interface or the proxy: convention.
      'lib/src/cache/cacheable_secondary_address_finder.dart': ['dart:io'],
      // `Socket getSocket()` — the root of the list.
      'lib/src/connection/at_connection.dart': ['dart:io'],
      'lib/src/connection/base_connection.dart': ['dart:io'],
      // Calls SecureSocket.connect directly, bypassing SecureSocketUtil.
      'lib/src/monitor_client.dart': ['dart:io'],
      // Certificates, SecurityContext and the TLS keylog: native by nature,
      // absorbed whole into the native transport rather than ported.
      'lib/src/util/secure_socket_util.dart': ['dart:io'],
    },
    // at_utils and chalkdart are inherited from the logger, not at_lookup's own
    // doing; they come off when the at_utils barrel split lands.
    expectedBlocked: const <String>{'at_lookup', 'at_utils', 'chalkdart'},
    minFilesWalked: 600,
  );
}
