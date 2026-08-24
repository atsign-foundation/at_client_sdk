import 'dart:convert' show jsonEncode;
import 'dart:io';

import 'package:pq_matrix_published/arm.dart' show publishedPreference;
import 'package:pq_matrix_scenario/pq_matrix_scenario.dart'
    show ClientSpec, attachWithoutKeySource, connect, readPeerApskAsReleasedReader;

/// What at_client **3.14.0** makes of an enrollment's `_apsk`.
///
/// A separate process because it is a separate BUILD: no single process can
/// hold two versions of one package, and the whole value of this program is
/// that it is the version pub.dev ships rather than a simulation of it.
///
/// It reads and reports; it decides nothing. The verdict — that a `pqReady`
/// advertisement is indistinguishable from a `legacy` one to a deployed peer,
/// and that a `pqActive` one is not — is asserted by the test that spawns
/// this, because a probe that judges its own output is a probe whose failure
/// mode is invisible.
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

  // One line, sentinel-prefixed: at_client logs to stdout too, and "the logger
  // is turned down" is a claim about levels rather than about the stream.
  stdout.writeln('##APSK##${jsonEncode(verdict)}');
  exit(0);
}
