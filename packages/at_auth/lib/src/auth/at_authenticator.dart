import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart' show RSAPrivateKey;

final _logger = AtSignLogger('AtAuthenticator');

/// CRAM waits far less than a verb response does: a secret is either accepted
/// promptly or not at all, and this leg runs during onboarding where a slow
/// failure is worse than a fast one.
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
/// - it returns keys — PKAM, signed with the keypair those keys hold for
///   [enrollmentId], under the algorithm that keypair names.
///
/// Nothing here reaches into at_lookup for key material, and at_lookup names
/// none of these types: `AtKeys` and `AtKeysIo` live in at_auth, which depends
/// on at_lookup, so the dependency only points one way.
AtAuthenticator authenticatorFor(
  AtKeysIo io,
  String atSign, {
  String? cramSecret,
  String? enrollmentId,
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
      return _pkam(executor, atSign, keys, enrollmentId, clientConfig);
    };

/// Authenticates with a CRAM secret alone, for a caller holding no keystore.
///
/// [authenticatorFor] also falls back to CRAM, but only for a caller that has
/// an [AtKeysIo] to read: it decides by that read throwing
/// [AtKeysSourceAbsentException].
AtAuthenticator authenticatorForCramSecret(
  String atSign,
  String cramSecret, {
  Map<String, dynamic> clientConfig = const {},
}) =>
    (executor) => _cram(executor, atSign, cramSecret, clientConfig);

/// The legacy credential: a PKAM private key and nothing else.
///
/// Reads no keystore, for a caller holding a PKAM private key and nothing
/// else. Signs with the private key alone, which is all RSA signing reads.
///
/// Always rsa2048: a keyless caller names no enrollment, so there is no
/// record to read an algorithm from, and rsa2048 is at_lookup's default.
AtAuthenticator authenticatorForPrivateKey(
  String atSign,
  String privateKey, {
  String? enrollmentId,
  Map<String, dynamic> clientConfig = const {},
}) =>
    (executor) async {
      _logger.finer('authenticating $atSign with a bare private key');
      var fromResponse = await executor.sendSync((FromVerbBuilder()
            ..atSign = atSign
            ..clientConfig = Map<String, dynamic>.from(clientConfig))
          .buildCommand());
      if (fromResponse.isEmpty) {
        return false;
      }
      fromResponse = fromResponse.trim().replaceFirst(RegExp(r'^data:'), '');
      fromResponse = validatedFromChallenge(fromResponse, atSign);

      final signature = _signRsaPkamChallenge(fromResponse, privateKey);

      final pkamResponse = await executor.sendSync((PkamVerbBuilder()
            ..signingAlgo = SigningAlgoType.rsa2048.name
            ..hashingAlgo = HashingAlgoType.sha256.name
            ..enrollmentlId = enrollmentId
            ..signature = signature)
          .buildCommand());
      if (pkamResponse == 'data:success') {
        _logger.info('pkam auth success for $atSign');
        return true;
      }
      throw UnAuthenticatedException(
          'Failed connecting to $atSign. $pkamResponse');
    };

/// Answers the atServer's `from:` challenge with a PKAM signature from [keys].
/// [validatedFromChallenge] refuses a challenge that does not name [atSign],
/// so a server cannot get this client to sign for somebody else.
Future<bool> _pkam(
  AtCommandExecutor executor,
  String atSign,
  AtKeys keys,
  String? enrollmentId,
  Map<String, dynamic> clientConfig,
) async {
  // NOTE: typed material this build cannot sign with is refused, never
  // signed for from the flat fields.
  final keyPair = keys.authenticationKeyPairFor(enrollmentId);
  if (keyPair == null) {
    throw AtKeyNotFoundException('AtKeys holds no authentication keypair for '
        '${enrollmentId ?? "this atSign's own credential"}, so there is '
        'nothing to sign the PKAM challenge with');
  }
  final signingAlgo = keyPair.algorithm;
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

  final signature = keyPair.algorithm == SigningAlgoType.rsa2048
      ? _signRsaPkamChallenge(fromResponse, keyPair.privateKey)
      : signPkamChallenge(keyPair, fromResponse);

  final pkamResponse = await executor.sendSync((PkamVerbBuilder()
        ..signingAlgo = signingAlgo.name
        ..hashingAlgo = hashingAlgo.name
        ..enrollmentlId = enrollmentId
        ..signature = signature)
      .buildCommand());
  if (pkamResponse == 'data:success') {
    _logger.info('pkam auth success for $atSign');
    return true;
  }
  throw UnAuthenticatedException('Failed connecting to $atSign. $pkamResponse');
}

/// Authenticates [atSign] by answering the atServer's `from:` challenge with
/// the SHA-512 digest of [cramSecret] and the challenge.
///
/// The challenge is digested as it arrives: unlike PKAM's, it does not pass
/// through [validatedFromChallenge]. A refusal throws an
/// [UnAuthenticatedException] naming [atSign] and the atServer's response.
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

  final digest =
      SHA512HashingAlgo().hash(utf8.encode('$cramSecret$fromResponse'));
  final cramResponse = await executor.sendSync('cram:$digest\n',
      maxWaitMilliSeconds: _cramMaxWaitMillis,
      transientWaitTimeMillis: _cramTransientWaitMillis);
  if (cramResponse == 'data:success') {
    _logger.info('cram auth success for $atSign');
    return true;
  }
  throw UnAuthenticatedException(
      'Cram authentication failed for $atSign: $cramResponse');
}

/// Signs [challenge] as a PKAM proof with [keyPair], returning the base64 the
/// `pkam:` verb carries.
///
/// The algorithm comes from the key material rather than from a caller, so a
/// key cannot be put through the wrong routine. An rsa2048 key must be 2048
/// bits here; the authenticators also sign a `pkam:` with a 1024-bit one.
String signPkamChallenge(
  ({SigningAlgoType algorithm, String publicKey, String privateKey}) keyPair,
  String challenge,
) {
  final data = Uint8List.fromList(utf8.encode(challenge));
  switch (keyPair.algorithm) {
    case SigningAlgoType.rsa2048:
      return base64Encode(RsaSignatureAlgo.rsa2048()
          .signBytesSync(data, secretKey: base64Decode(keyPair.privateKey)));
    case SigningAlgoType.mldsa65:
      return base64Encode(MlDsa65PureDartAlgo.signBytesSync(data,
          secretKey: _mlDsaSecretKey(keyPair.privateKey)));
    default:
      throw AtSigningException(
          'a PKAM challenge cannot be signed with ${keyPair.algorithm.name}: '
          'this build signs one with rsa2048 or mldsa65');
  }
}

/// Base64 of [challenge] signed by [privateKey], a base64 PKCS#8 RSA private
/// key, for a `pkam:` naming rsa2048.
///
/// Signs with a 1024-bit key as well as a 2048-bit one; [RsaSignatureAlgo]
/// refuses every other size.
String _signRsaPkamChallenge(String challenge, String privateKey) {
  final data = Uint8List.fromList(utf8.encode(challenge));
  final key = _rsaPrivateKeyOrNull(privateKey);
  if (key != null && key.asPointyCastle.n?.bitLength == 1024) {
    return base64Encode(key.createSHA256Signature(data));
  }
  return base64Encode(RsaSignatureAlgo.rsa2048()
      .signBytesSync(data, secretKey: base64Decode(privateKey)));
}

/// Null when [base64Key] is not a readable RSA private key, which
/// [RsaSignatureAlgo] then reports.
RSAPrivateKey? _rsaPrivateKeyOrNull(String base64Key) {
  try {
    return RSAPrivateKey.fromString(base64Key);
  } catch (_) {
    return null;
  }
}

/// [base64Key] as an ML-DSA-65 secret key, refused with what went wrong.
///
/// The length is checked here rather than left to the algorithm because this
/// is the last frame that knows the key was offered as a PKAM credential. A
/// PKAM key of about 1.2 kB is an RSA-2048 private key, and the way a caller
/// holds one while naming mldsa65 is a retrofitted keyfile: its flat fields
/// carry the original enrollment's RSA pair beside the new enrollment's
/// ML-DSA material, and the two are selected separately.
Uint8List _mlDsaSecretKey(String base64Key) {
  final Uint8List secretKey;
  try {
    secretKey = base64Decode(base64Key);
  } on FormatException {
    throw AtSigningException('an mldsa65 PKAM private key must be base64 of '
        'the raw ML-DSA-65 secret key');
  }
  if (secretKey.length != MlDsa65Sizes.secretKeyBytes) {
    throw AtSigningException(
        'this PKAM key is ${secretKey.length} bytes, and an ML-DSA-65 secret '
        'key is ${MlDsa65Sizes.secretKeyBytes}. '
        '${secretKey.length > 1000 && secretKey.length < 1400 ? 'A key this size is an RSA-2048 private key, so the declared '
            'algorithm and the credentials most likely come from different '
            'enrollments — check that the enrollment id being authenticated '
            'as is the one whose key material was loaded. ' : ''}'
        'Signing was not attempted');
  }
  return secretKey;
}
