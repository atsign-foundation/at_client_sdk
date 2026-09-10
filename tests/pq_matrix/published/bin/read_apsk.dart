import 'dart:convert' show jsonEncode;
import 'dart:io';

import 'package:pq_matrix_published/arm.dart' show publishedPreference;
import 'package:pq_matrix_scenario/pq_matrix_scenario.dart'
    show ClientSpec, attachWithoutKeySource, connect, readPeerApskAsReleasedReader;

/// Reports what at_client **3.14.0** makes of an enrollment's `_apsk`.
///
/// A separate process because no single process can hold two versions of one
/// package; it judges nothing, writing one `##APSK##`-prefixed JSON line to
/// stdout for its caller to assert on.
Future<void> main(List<String> args) async {
  String arg(String name) {
    final i = args.indexOf('--$name');
    if (i < 0 || i + 1 >= args.length) {
      throw ArgumentError('missing --$name');
    }
    return args[i + 1];
  }

  final peerAtSign = arg('peer');
  final peerEnrollmentId = arg('peer-enrollment-id');

  final spec = ClientSpec(
    atSign: arg('atsign'),
    namespace: arg('namespace'),
    rootDomain: arg('root-domain'),
    rootPort: int.parse(arg('root-port')),
    storagePath: arg('storage'),
  );

  final client = await connect(
    spec: spec,
    preference: publishedPreference(spec, 'published'),
    attach: attachWithoutKeySource,
  );

  final verdict = await readPeerApskAsReleasedReader(
      client, peerAtSign, peerEnrollmentId);

  // NOTE: at_client logs to stdout too, so the result carries a sentinel
  // prefix for the caller to pick out.
  stdout.writeln('##APSK##${jsonEncode(verdict)}');
  exit(0);
}
