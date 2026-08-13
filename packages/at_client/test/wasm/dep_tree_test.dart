// These gates read the filesystem to inspect sources, so they run on the VM
// only. Without this they would be compiled and launched by the T2
// node+dart2wasm platform run, where dart:io throws and the failure looks like a
// neutrality problem rather than a test that was never meant to run there.
@TestOn('vm')
library;

import 'package:test/test.dart'; // for the @TestOn annotation above
import 'package:wasm_shakedown/ratchet.dart';

/// Dependency-tree ratchet for at_client's public barrels.
///
/// This is the top of the graph, so this baseline is the honest summary of how
/// far the neutrality work has to go: seven at_client sources and ten blocked
/// packages, most of them inherited.
///
/// One absence is worth as much as the entries. `lib/src/manager/
/// sync_isolate_manager.dart` is the only `dart:isolate` file in any `lib/` in
/// the repo, and it is **not** in this list — it is deprecated and unreachable
/// from the barrels, which is why deleting it is safe. It is also a neat
/// illustration of why a compile gate would not do: `dart compile wasm` accepts
/// both `dart:io` and `dart:isolate`, so that file would never have been flagged
/// whether it was reachable or not.
///
/// Baselines taken 2026-08-13 against trunk `20f7f4da5`. Regenerate with
/// `dart run wasm_shakedown:baseline <barrel>`.
void main() {
  for (final barrel in const [
    'package:at_client/at_client.dart',
    'package:at_client/at_client_mixins.dart',
  ]) {
    // Both barrels reach the same graph, so they share one baseline. Asserting
    // them separately still earns its keep: it is what would catch the mixins
    // barrel growing an import the main barrel does not have.
    ratchetGroup(
      barrel,
      package: 'at_client',
      expectedOffenders: const <String, List<String>>{
        // A second, non-injectable RemoteSecondary construction plus the file
        // transfer surface.
        'lib/src/client/at_client_impl.dart': ['dart:io'],
        // `List<File>` in uploadFile / downloadFile / reuploadFiles — the spec
        // is exported, so this one is in the public API, not an implementation
        // detail.
        'lib/src/client/at_client_spec.dart': ['dart:io'],
        // Constructs AtLookupImpl without passing the socket factories, and uses
        // the connectivity checker.
        'lib/src/client/remote_secondary.dart': ['dart:io'],
        // Accepts a MonitorOutboundConnectionFactory that nothing passes.
        'lib/src/manager/monitor.dart': ['dart:io'],
        'lib/src/service/encryption_service.dart': ['dart:io'],
        // Top-level http.post/get with no injectable client.
        'lib/src/service/file_transfer_service.dart': ['dart:io'],
        // Calls SecureSocket.connect directly.
        'lib/src/stream/stream_notification_handler.dart': ['dart:io'],
      },
      expectedBlocked: const <String>{
        'archive',
        'at_auth',
        'at_client',
        'at_lookup',
        'at_persistence_secondary_server',
        'at_server_status',
        'at_utils',
        'chalkdart',
        'http',
        'internet_connection_checker',
      },
      minFilesWalked: 1100,
    );
  }
}
