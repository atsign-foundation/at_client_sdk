import 'dart:typed_data';

import 'package:at_chops/src/algorithm/algo_type.dart';
import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/default_signing_algo.dart';
import 'package:at_chops/src/algorithm/ecc_signing_algo.dart';
import 'package:at_chops/src/algorithm/pkam_signing_algo.dart';

/// Represents input attributes required for data signing.
///
///   [_data] input data to be signed
///  [hashingAlgoType] - Hashing algorithm used to hash the input data. Refer [HashingAlgoType]
///  [signingAlgoType] - Signing algorithm used to generate signature for the input data. Refer [SigningAlgoType]
class AtSigningInput {
  /// Data that needs to be signed
  ///
  /// Data either needs to be of type [String] or [Uint8List]
  ///
  /// AtException will be thrown if data is of any other type
  final dynamic _data;

  /// Choose [HashingAlgoType] from [HashingAlgoType.values]
  ///
  /// Default value will be [HashingAlgoType.sha256]
  HashingAlgoType hashingAlgoType = HashingAlgoType.sha256;

  /// Choose [SigningAlgoType] from [SigningAlgoType.values]
  ///
  /// Default value will be [SigningAlgoType.rsa2048]
  SigningAlgoType signingAlgoType = SigningAlgoType.rsa2048;

  /// SigningAlgorithm that will be used to sign/verify data
  ///
  /// Available implementations are [DefaultSigningAlgo], [PkamSigningAlgo], [EccSigningAlgo]. Callers can set their own signing algorithm by implementing [AtSigningAlgorithm]
  AtSigningAlgorithm? signingAlgorithm;

  /// Select signingMode from [AtSigningMode]
  ///
  /// Use [AtSigningMode.data] for general data signing
  ///
  /// Use [AtSigningMode.pkam] for pkam challenge signing
  AtSigningMode? signingMode;

  AtSigningInput(this._data);

  dynamic get data => _data;

  @override
  String toString() {
    return 'AtSigningInput{_data: $_data, hashingAlgoType: $hashingAlgoType, signingAlgoType: $signingAlgoType, signingAlgorithm: $signingAlgorithm, signingMode: $signingMode}';
  }
}

/// Input for data signature verification
///
/// [_data], [_signature] and [_publicKey] fields are required for successful
/// verification of data signature
///  [hashingAlgoType] - Hashing algorithm used to hash the input data. Refer [HashingAlgoType]
///  [signingAlgoType] - Signing algorithm used to verify signature for the input data. Refer [SigningAlgoType]
class AtSigningVerificationInput {
  /// Data that has to verified
  ///
  /// Data has to be either of [String] or [Uint8List]
  final dynamic _data;

  /// Signature of [_data] that will be used to verify
  ///
  /// Signature has to be base64decoded if signing result is base64Encoded.
  final dynamic _signature;

  /// Mandatory input
  ///
  /// PublicKey from AsymmetricKeypair whose private key was used to compute [_signature]
  final String _publicKey;

  /// Choose [HashingAlgoType] from [HashingAlgoType.values]
  ///
  /// Default [HashingAlgoType] will be [HashingAlgoType.sha256]
  HashingAlgoType hashingAlgoType = HashingAlgoType.sha256;

  /// Choose [SigningAlgoType] from [SigningAlgoType.values]
  ///
  /// Default [SigningAlgoType] will be [SigningAlgoType.rsa2048]
  SigningAlgoType signingAlgoType = SigningAlgoType.rsa2048;

  /// Select signingMode from [AtSigningMode]
  ///
  /// Use [AtSigningMode.data] for a general purpose signing
  ///
  /// Use [AtSigningMode.pkam] when signing pkam challenges
  AtSigningMode? signingMode;

  /// SigningAlgorithm that will be used to sign/verify data
  ///
  /// Available options are [DefaultSigningAlgo], [PkamSigningAlgo], [EccSigningAlgo]
  AtSigningAlgorithm? signingAlgorithm;

  AtSigningVerificationInput(this._data, this._signature, this._publicKey);

  dynamic get data => _data;

  dynamic get signature => _signature;

  String get publicKey => _publicKey;

  @override
  String toString() {
    return 'AtSigningVerificationInput{_data: $_data, _signature: $_signature, _publicKey: $_publicKey, hashingAlgoType: $hashingAlgoType, signingAlgoType: $signingAlgoType, signingMode: $signingMode, signingAlgorithm: $signingAlgorithm}';
  }
}

enum AtSigningMode { pkam, data, sim }
