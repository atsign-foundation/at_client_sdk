// The enrollment key-package surface is @experimental; driving it is how each
// stage gets an enrollment whose `_apsk` a released peer can be asked about.
// ignore_for_file: experimental_member_use

@Timeout(Duration(minutes: 15))
@Tags(['pq'])
library;

import 'dart:convert' show LineSplitter, jsonDecode;
import 'dart:io';

import 'package:at_auth/at_auth.dart' show AtKeys, InMemoryAtKeysIo;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show AtClientSecretSharing;
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart'
    show EnrolledClient, enrolAndAuthenticate;
import 'package:test/test.dart';

import 'test_utils.dart';

/// UC-G1.14 — a `pqReady` sender is invisible to a **deployed** peer.
///
/// The one measurement in this project that genuinely needs a second build of
/// at_client, and therefore the one thing that survived the rollout matrix.
/// Everything else the matrix did now runs in one process in
/// `pq_posture_grid_test.dart`, which it can precisely because it no longer
/// has a released arm among its cells.
///
/// The question is not what this tree believes it published. It is what a
/// build nobody here can change makes of it — so the reader is at_client
/// **3.14.0** resolved from pub.dev, spawned as its own process because no
/// single process can hold two versions of one package.
///
/// The row needs three stages and all three are load-bearing:
///
/// - **legacy** is the baseline: what a deployed peer does with an
///   advertisement today.
/// - **pqReady** is the claim: it must parse as an RSA public key exactly as
///   legacy does, AND must be a different key — a stage that published
///   nothing new would also "look the same", and that is the reading this
///   control excludes.
/// - **pqActive** is the second control: `rsa: true` has to be capable of
///   being false, or the first two assertions pass for a reader that says yes
///   to anything.
void main() {
  final atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'] as String;
  final namespace = 'wavi';

  final publishedDir = Directory(
      '${Directory.current.path}/../pq_matrix/published');

  const stages = <String, PqPosture>{
    'legacy': PqPosture.legacy,
    'pqReady': PqPosture.pqReady,
    'pqActive': PqPosture.pqActive,
  };

  final cells = <String, EnrolledClient>{};

  /// What at_client 3.14.0 makes of [stage]'s advertisement.
  Future<Map<String, Object?>> askReleasedPeer(String stage) async {
    final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final result = await Process.run(
      'dart',
      [
        'run',
        'bin/read_apsk.dart',
        '--atsign', atSign,
        '--peer', atSign,
        '--peer-enrollment-id', cells[stage]!.client.enrollmentId!,
        '--namespace', namespace,
        '--root-domain', 'vip.ve.atsign.zone',
        '--root-port', '${TestUtils.rootServerPort}',
        '--storage', 'test/hive/relpeer/$stage-$runId',
        '--run-id', runId,
      ],
      workingDirectory: publishedDir.path,
    );

    // The sentinel exists because at_client logs to stdout too, and "the
    // logger is turned down" is a claim about levels rather than the stream.
    final line = const LineSplitter()
        .convert('${result.stdout}')
        .where((l) => l.startsWith('##APSK##'))
        .toList();
    expect(line, hasLength(1),
        reason: 'the released reader printed no verdict for $stage.\n'
            'exit ${result.exitCode}\n'
            'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    return (jsonDecode(line.single.substring('##APSK##'.length)) as Map)
        .cast<String, Object?>();
  }

  setUpAll(() async {
    expect(publishedDir.existsSync(), isTrue,
        reason: 'the released arm lives at ${publishedDir.path}; without it '
            'this row has no reader and nothing else in the tree compares '
            "this tree's legacy posture against a released at_client");

    // The control arm's lockfile is committed and its at_client pin is exact,
    // so this resolves what it always resolved rather than whatever is newest.
    final pubGet = await Process.run('dart', ['pub', 'get'],
        workingDirectory: publishedDir.path);
    expect(pubGet.exitCode, 0,
        reason: 'pub get failed in the released arm:\n'
            '${pubGet.stdout}\n${pubGet.stderr}');

    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final loader = AtEncryptionKeysLoader.getInstance();
    final manager = await AtClientManager(atSign).setCurrentAtSign(
        atSign, namespace, TestUtils.getPreference(atSign),
        atKeysIo: keysIo,
        atChops: loader.createAtChopsFromDemoKeys(atSign));
    await loader.setEncryptionKeys(manager.atClient, atSign);
    await AtClientSecretSharing.forClient(manager.atClient).register();

    for (final entry in stages.entries) {
      cells[entry.key] = await enrolAndAuthenticate(
        approver: manager.atClient,
        atSign: atSign,
        namespace: namespace,
        preference: TestUtils.getPreference(atSign, posture: entry.value),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        // `(appName, deviceName)` is one-shot server state, so a second run
        // against the same virtualenv must not collide with the first's.
        deviceName: 'relpeer-${entry.key}-'
            '${DateTime.now().microsecondsSinceEpoch}',
      );
      // The id the client is RUNNING as, not the one it was enrolled as: a pq
      // posture retrofits itself during construction and advertises its
      // `_apsk` under the new id. Asking about the enrolled id would ask about
      // a record the retrofit left behind.
      stdout.writeln('##RELPEER## ${entry.key} runs as '
          '${cells[entry.key]!.client.enrollmentId}');
    }
  });

  test('UC-G1.14 · pqReady is invisible to a deployed peer', () async {
    final asLegacy = await askReleasedPeer('legacy');
    final asPqReady = await askReleasedPeer('pqReady');
    final asPqActive = await askReleasedPeer('pqActive');

    for (final entry in {
      'legacy': asLegacy,
      'pqReady': asPqReady,
      'pqActive': asPqActive
    }.entries) {
      stdout.writeln('##RELPEER## ${entry.key}: fetched='
          '${entry.value['fetched']} rsa=${entry.value['rsa']}');
    }

    // The baseline.
    expect(asLegacy['fetched'], true, reason: '${asLegacy['error']}');
    expect(asLegacy['rsa'], true,
        reason: 'the released reader must parse a legacy sender\'s _apsk as '
            'an RSA public key. If it cannot, this tree has already broken '
            'every deployed peer and the rest of the row is moot');

    // The claim.
    expect(asPqReady['fetched'], true, reason: '${asPqReady['error']}');
    expect(asPqReady['rsa'], true,
        reason: 'a pqReady enrollment advertises its own freshly minted '
            'RSA-2048 signing key, and a single active rsa2048 entry spells '
            'as the bare string — so a deployed peer cannot tell it from a '
            'legacy sender. If this is false, rollout stage 1 is visible to '
            'the fleet and the staged rollout does not work');

    // Positive control 1: "looks the same" must not mean "published nothing".
    expect(asPqReady['value'], isNot(asLegacy['value']),
        reason: 'pqReady must publish a DIFFERENT key from legacy — its own '
            'signing key rather than its APKAM authentication key. Identical '
            'values would satisfy the assertion above while meaning the stage '
            'did nothing at all');

    // Positive control 2: `rsa: true` must be capable of being false.
    expect(asPqActive['rsa'], false,
        reason: 'pqActive publishes the JSON array form, which is the one a '
            'released reader cannot parse. If this is ALSO true then the '
            'reader says yes to anything and the two assertions above are '
            'measuring nothing');
  });
}
