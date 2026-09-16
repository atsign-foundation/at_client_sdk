/// Guards asserted against the SOURCE TREE rather than against behaviour.
///
/// These read library source and check what it contains, the only way to
/// assert that a code path does not exist at all. They fail differently from
/// everything else in this directory — a rename breaks the grep while the
/// behaviour is intact — so they are declared as guards rather than burn-down
/// rows in `manifest.dart`.
///
/// Catalogue: the PQ acceptance catalogue.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'manifest.dart';

void main() {
  test('metadata reaches the wire through one serializer', () {
    // One serializer serves both the stored key and the notification frame. A
    // second, hand-rolled one falls behind it silently: appMetadata stops
    // reaching the atServer and every cross-atSign read falls back to the legacy provider,
    // with no error anywhere. The absence of a rival serializer is what no
    // runtime assertion can see, which is why this is a source-text check.
    final lib = Directory('${repoRoot().path}/packages/at_client/lib/src');
    for (final path in const [
      'service/sync_service_impl.dart',
    ]) {
      expect(File('${lib.path}/$path').readAsStringSync(),
          contains('toAtProtocolFragment'),
          reason: '$path must serialize metadata through the shared fragment '
              'builder; a private one beside it is how appMetadata silently '
              'stopped reaching the atServer once already');
    }

    expect(
        File('${lib.path}/service/notification_service_impl.dart')
            .readAsStringSync(),
        isNot(contains("'notify:id:")),
        reason: 'notification_service_impl.dart must not compose a notify '
            'command by hand — NotifyVerbBuilder is the one that serializes '
            'metadata into the frame, and a second one beside it drifts');
  });

  test('the verifier has no accept lever for signatures', () {
    // A verifier resolves the strongest algorithm the two documents share and
    // applies no floor to the result, so it cannot decline an algorithm it
    // implements: nothing anywhere lets a verifier say which algorithms it will
    // accept a SIGNATURE under. Source-shaped deliberately — the behavioural
    // form would stay GREEN on the day an accept lever landed, since such a
    // lever cannot ship default-deny without refusing every envelope already
    // stored. This one goes red the moment the parameter or the field appears.
    final root = repoRoot().path;
    final signing = File('$root/packages/at_client/lib/src/signing/'
            'envelope_signature.dart')
        .readAsStringSync();
    final prefs = File('$root/packages/at_client/lib/src/preference/'
            'at_client_preference.dart')
        .readAsStringSync();

    final decl = RegExp(r'Future<void> verifyEnvelope\(([^)]*)\)', dotAll: true)
        .firstMatch(signing);
    expect(decl, isNotNull,
        reason: 'verifyEnvelope is the verification entry point and this guard '
            'is about its parameters. If it has been renamed or reshaped, this '
            'guard is measuring nothing and must be rewritten rather than '
            'deleted');
    final params = decl!.group(1)!;
    expect(params, contains('signerPublicKey'),
        reason: 'the second positive control: the parameter list really was '
            'captured, rather than an empty match reading as "no accept '
            'parameter"');
    expect(params, isNot(contains('ccept')),
        reason: 'verifyEnvelope takes the envelope, the signer\'s advertised '
            'key and the expected type - and nothing by which a caller could '
            'narrow what it will accept. When step 3 lands, this is where the '
            'set arrives and this guard is the prompt to make the clause true');

    // The preference's algorithm-typed fields, named exhaustively. None is an
    // accept side for signatures; the one accept-shaped field in the class,
    // disallowLegacyEncryption, exempts reads by design.
    const algorithmFields = <String>[
      'dataSigningKeyAlgorithms',
      'authenticationKeyAlgorithm',
      'sealsToKeyAlgorithms',
      'keyEstablishmentAlgorithms',
      'signingAlgoType',
      'hashingAlgoType',
    ];
    for (final field in algorithmFields) {
      expect(prefs, contains(field),
          reason: 'the census is asserted PRESENT before it is asserted '
              'complete - a renamed field would otherwise shrink the set '
              'silently and make the absence below vacuous');
    }
    final declared = RegExp(r'^  (?:final )?[A-Za-z<>?, ]+ (\w*[Aa]lgo\w*);',
            multiLine: true)
        .allMatches(prefs)
        .map((m) => m.group(1)!)
        .toSet();
    expect(declared.difference(algorithmFields.toSet()), isEmpty,
        reason: 'AtClientPreference has gained an algorithm-typed field this '
            'guard does not know about. If it is an accept lever for '
            'signatures, UC-G2.9 c1 has stopped being true and the clause '
            'needs rewriting, not this guard relaxing');
  });

  test('the signing root has no namespace push', () {
    // `pushSecretToNamespaceMembers` is the mint/rotation fan-out: it
    // enumerates a namespace's members and seals the secret to each of their
    // key packages. The signing root is atSign-level and carries no namespace,
    // so there is no roster for it to enumerate — an enrollment that missed
    // the approval-time conveyance asks a holder for the private instead. That
    // absence is the invariant, and no runtime assertion can see it: a path
    // that is never taken and a path that does not exist look identical from
    // outside.
    const capability = 'pushSecretToNamespaceMembers';
    const declaredIn = 'secret_sharing/pairwise_secret_sharing.dart';
    const callers = <String>[
      'crypto/nskey/nskey_seeding.dart',
      'crypto/nskey/nskey_rotation.dart',
    ];
    const signingRoot = 'crypto/nskey/pq_signing_root.dart';
    final lib = Directory('${repoRoot().path}/packages/at_client/lib/src');

    expect(File('${lib.path}/$declaredIn').readAsStringSync(),
        contains('Future<int> $capability('),
        reason: '$declaredIn must still declare $capability under that name. '
            'Everything below is a string match, so a rename leaves the '
            'absence this guard asserts matching nothing, and it would pass '
            'for a reason that has nothing to do with the signing root');

    for (final path in callers) {
      expect(File('${lib.path}/$path').readAsStringSync(),
          contains('$capability('),
          reason: '$path must still call $capability. The two call sites are '
              'this guard\'s positive control: an absence asserted with no '
              'live use of the name left in the tree measures nothing');
    }

    expect(File('${lib.path}/$signingRoot').readAsStringSync(),
        isNot(contains(capability)),
        reason: 'the signing root must not push its private to namespace '
            'members. It carries no namespace, so the fan-out has no roster to '
            'enumerate, and pushing anyway would send the key that vouches for '
            'every enrollment on the atSign to whatever roster some namespace '
            'happened to return. The route for an enrollment that does not '
            'hold it is to ask for it');

    // Nor may anything wrap the fan-out: a delegating method elsewhere would
    // let the signing root push while naming nothing the check above greps for.
    final unexpected = <String>[];
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = entity.path.substring(lib.path.length + 1);
      if (relative == declaredIn || callers.contains(relative)) continue;
      if (entity.readAsStringSync().contains(capability)) {
        unexpected.add(relative);
      }
    }
    expect(unexpected, isEmpty,
        reason: 'a file under lib/src names $capability that this guard does '
            'not know about. A genuine new call site belongs in the caller '
            'list here; a method that DELEGATES to the fan-out has to be named '
            'in the absence check above as well, or the signing root can push '
            'through it while naming the capability nowhere itself');
  });

  test('every test file here is declared as a scenario file or a guard', () {
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
