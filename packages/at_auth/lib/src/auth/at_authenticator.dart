import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

final _logger = AtSignLogger('AtAuthenticator');

/// CRAM waits far less than a verb response does: a secret is either accepted
/// promptly or not at all, and this leg runs during onboarding where a slow
/// failure is worse than a fast one. The values are at_lookup's own, kept so
/// that moving this code changes no timing.
const _cramMaxWaitMillis = 10000;
const _cramTransientWaitMillis = 4000;

/// Builds the authenticator for [atSign], reading its credentials from [io].
///
/// The returned closure is safe to hold for an instance's lifetime. It reads
/// [io] on **every** invocation rather than closing over the keys, so an
/// instance that CRAM-onboards and later PKAM-authenticates gets the right
/// answer both times without anyone telling it that the phase changed. Storing
/// the phase would be a second copy of something the keystore already knows,
/// and the two could disagree.
///
/// Which credential applies is decided by whether [io] has anything to give:
///
/// - it throws [AtKeysSourceAbsentException] — there is no keyfile yet, so
///   this atSign is not onboarded and CRAM is the only credential that exists;
/// - it returns keys — PKAM, signed with the algorithm those keys name for
///   [enrollmentId].
///
/// [chops] lets a caller supply its own signer, which `AtAuth` has always
/// allowed through `AtAuth.create(atChops:)` and its mutable `atChops` field.
/// When supplied, only the *algorithm* is taken from the keyfile - the keypair
/// is the caller's. Resolving the keyfile's own signer eagerly would be worse
/// than wasteful: it throws on a keyfile missing material that a caller with
/// its own signer never needed.
///
/// [signingAlgo] overrides the algorithm the keyfile would name. Onboarding a
/// PQ-native atSign is the case that needs it: the keypair was minted moments
/// earlier and is in no keyfile, under an enrollment the atServer has not
/// created yet, so nothing can be resolved and the rsa2048 default would sign
/// an ML-DSA key with the RSA routine.
///
/// Nothing here reaches into at_lookup for key material, and at_lookup names
/// none of these types: `AtKeys` and `AtKeysIo` live in at_auth, which depends
/// on at_lookup, so the dependency only points one way.
AtAuthenticator authenticatorFor(
  AtKeysIo io,
  String atSign, {
  String? cramSecret,
  String? enrollmentId,
  AtChops? chops,
  SigningAlgoType? signingAlgo,
  Map<String, dynamic> clientConfig = const {},
}) =>
    (executor) async {
      final AtKeys keys;
      try {
        keys = await io.read(atSign);
      } on AtKeysSourceAbsentException {
        if (cramSecret == null) {
          throw UnAuthenticatedException(
              'No keys for $atSign and no CRAM secret to onboard with, so '
              'there is no credential to authenticate with');
        }
        _logger.finer('no keyfile for $atSign - authenticating with CRAM');
        return _cram(executor, atSign, cramSecret, clientConfig);
      }
      return _pkam(executor, atSign, keys, enrollmentId, clientConfig, chops,
          signingAlgo);
    };

/// Ported from `AtLookupImpl.pkamAuthenticate`, which keeps the challenge
/// validation: [validatedFromChallenge] refuses a challenge that does not name
/// [atSign], so a server cannot get this client to sign for somebody else.
Future<bool> _pkam(
  AtCommandExecutor executor,
  String atSign,
  AtKeys keys,
  String? enrollmentId,
  Map<String, dynamic> clientConfig,
  AtChops? injectedChops,
  SigningAlgoType? injectedAlgo,
) async {
  // A null algorithm means the flat fields' RSA keypair, which is what
  // at_lookup signs with by default - so a legacy enrollment is rsa2048.
  final AtChops signer;
  final SigningAlgoType signingAlgo;
  if (injectedAlgo != null) {
    // The caller named the algorithm because the keystore cannot answer. A
    // PQ-native activation signs with a keypair minted moments ago, under an
    // enrollment the atServer has not created yet, so there is nothing to
    // resolve from - and the default would sign an ML-DSA key with the RSA
    // routine.
    signer = injectedChops ?? keys.authenticationFor(enrollmentId).chops;
    signingAlgo = injectedAlgo;
  } else if (injectedChops != null) {
    // The caller brought its own signer - a hardware-backed one, say. Take
    // only the ALGORITHM from the keyfile: `authenticationFor` would build an
    // AtChops this call is about to discard, and it throws on a keyfile
    // missing material a caller with its own signer never needed.
    signer = injectedChops;
    signingAlgo =
        keys.authenticationAlgorithmFor(enrollmentId) ?? SigningAlgoType.rsa2048;
  } else {
    final resolved = keys.authenticationFor(enrollmentId);
    signer = resolved.chops;
    signingAlgo = resolved.algorithm ?? SigningAlgoType.rsa2048;
  }
  const hashingAlgo = HashingAlgoType.sha256;

  var fromResponse = await executor.sendSync((FromVerbBuilder()
        ..atSign = atSign
        ..clientConfig = Map<String, dynamic>.from(clientConfig))
      .buildCommand());
  if (fromResponse.isEmpty) {
    return false;
  }
  fromResponse = fromResponse.trim().replaceFirst(RegExp(r'^data:'), '');
  fromResponse = validatedFromChallenge(fromResponse, atSign);

  final signingResult = signer.sign(AtSigningInput(fromResponse)
    ..signingAlgoType = signingAlgo
    ..hashingAlgoType = hashingAlgo
    ..signingMode = AtSigningMode.pkam);

  final pkamResponse = await executor.sendSync((PkamVerbBuilder()
        ..signingAlgo = signingAlgo.name
        ..hashingAlgo = hashingAlgo.name
        ..enrollmentlId = enrollmentId
        ..signature = signingResult.result)
      .buildCommand());
  if (pkamResponse == 'data:success') {
    _logger.info('pkam auth success for $atSign');
    return true;
  }
  throw UnAuthenticatedException(
      'Failed connecting to $atSign. $pkamResponse');
}

/// Ported from `AtLookupImpl.cramAuthenticate`, verbatim - including that it
/// does NOT pass the challenge through [validatedFromChallenge], where PKAM
/// does. That asymmetry is recorded in
/// `docs/projects/at-lookup-consolidation/plan.md` section 6 and is
/// deliberately not resolved by moving this code: a port that quietly adds a
/// check is a behaviour change hiding inside a refactor.
Future<bool> _cram(
  AtCommandExecutor executor,
  String atSign,
  String cramSecret,
  Map<String, dynamic> clientConfig,
) async {
  var fromResponse = await executor.sendSync(
      (FromVerbBuilder()
            ..atSign = atSign
            ..clientConfig = Map<String, dynamic>.from(clientConfig))
          .buildCommand(),
      maxWaitMilliSeconds: _cramMaxWaitMillis,
      transientWaitTimeMillis: _cramTransientWaitMillis);
  if (fromResponse.isEmpty) {
    return false;
  }
  fromResponse = fromResponse.trim().replaceFirst(RegExp(r'^data:'), '');

  final digest = SHA512HashingAlgo().hash(utf8.encode('$cramSecret$fromResponse'));
  final cramResponse = await executor.sendSync('cram:$digest\n',
      maxWaitMilliSeconds: _cramMaxWaitMillis,
      transientWaitTimeMillis: _cramTransientWaitMillis);
  if (cramResponse == 'data:success') {
    _logger.info('cram auth success for $atSign');
    return true;
  }
  throw UnAuthenticatedException('Auth failed');
}
