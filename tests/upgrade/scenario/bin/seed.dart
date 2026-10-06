import 'dart:convert' show jsonEncode;
import 'dart:io';

import 'package:upgrade_scenario/upgrade_scenario.dart';

/// Seeds a store with whichever at_client the calling package resolves, then
/// reports what that version observes of it.
///
/// Run from a released arm as `dart run upgrade_scenario:seed`. It judges
/// nothing: it writes one `##UPGRADE##`-prefixed JSON line to stdout, holding
/// the seed's preconditions and the snapshot, for its caller to assert on.
/// It exits without waiting for its last write to reach the atServer, so the
/// next version may find it still to push.
Future<void> main(List<String> args) async {
  String arg(String name) {
    final i = args.indexOf('--$name');
    if (i < 0 || i + 1 >= args.length) {
      throw ArgumentError('missing --$name');
    }
    return args[i + 1];
  }

  final me = arg('atsign');
  final peer = arg('peer');
  final spec = ClientSpec(
    atSign: me,
    namespace: arg('namespace'),
    rootDomain: arg('root-domain'),
    rootPort: int.parse(arg('root-port')),
    storagePath: arg('storage'),
  );

  final client = await connect(
      spec: spec,
      preference: upgradePreference(spec),
      attach: attachWithoutKeySource);
  final facts =
      await seed(client, me: me, peer: peer, namespace: spec.namespace);
  await writePending(client, me: me, peer: peer, namespace: spec.namespace);
  final observed =
      await snapshot(client, me: me, peer: peer, namespace: spec.namespace);

  // NOTE: at_client logs to stdout too, so the report carries a sentinel
  // prefix for the caller to pick out.
  stdout.writeln(
      '##UPGRADE##${jsonEncode({'facts': facts, 'snapshot': observed})}');
  await stdout.flush();
  exit(0);
}
