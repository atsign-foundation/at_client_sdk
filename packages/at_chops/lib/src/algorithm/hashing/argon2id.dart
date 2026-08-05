import 'dart:async';
import 'dart:convert';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/hashing/types.dart';
import 'package:cryptography/cryptography.dart';

/// A class that implements the Argon2id hashing algorithm for password hashing.
///
/// This class provides a method to hash a given password using the Argon2id
/// algorithm, which is a memory-hard, CPU-intensive key derivation function
/// suitable for password hashing and encryption key derivation.
///
/// The class uses the `cryptography` package's `Argon2id` algorithm for deriving
/// a key from a password and encodes the result into a Base64 string.
class Argon2idHashingAlgo implements AtHashingAlgorithm<String, String> {
  /// Hashes a given password using the Argon2id algorithm.
  ///
  /// The [password] parameter is required, and it represents the password or
  /// passphrase to be hashed.
  ///
  /// The [hashParams] parameter is optional. It allows customizing the Argon2id
  /// parameters, such as:
  /// - [HashParams.parallelism]: The degree of parallelism (threads) to use.
  /// - [HashParams.memory]: The amount of memory (in KB) to use.
  /// - [HashParams.iterations]: The number of iterations (time cost) to apply.
  /// - [HashParams.hashLength]: The length of the resulting hash (in bytes).
  ///
  /// If [hashParams] is not provided, default values will be used.
  ///
  /// The method returns a [Future] that resolves to a Base64-encoded string
  /// representing the hashed value of the input password.
  ///
  /// Throws:
  /// - [ArgumentError] if the provided password is null or empty.
  ///
  /// Returns a Base64-encoded string representing the derived key.
  @override
  Future<String> hash(String password, {ArgonHashParams? hashParams}) async {
    hashParams ??= ArgonHashParams();
    final argon2id = Argon2id(
        parallelism: hashParams.parallelism,
        memory: hashParams.memory,
        iterations: hashParams.iterations,
        hashLength: hashParams.hashLength);

    SecretKey secretKey = await argon2id.deriveKeyFromPassword(
        password: password, nonce: password.codeUnits);

    return Base64Encoder().convert(await secretKey.extractBytes());
  }
}
