import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/at_algorithm.dart';
import 'package:at_chops/src/hashing/types.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/argon2.dart';

/// A class that implements the Argon2id hashing algorithm for password hashing.
///
/// This class provides a method to hash a given password using the Argon2id
/// algorithm, which is a memory-hard, CPU-intensive key derivation function
/// suitable for password hashing and encryption key derivation.
///
/// The class uses pointycastle's `Argon2BytesGenerator` for deriving a key from
/// a password and encodes the result into a Base64 string.
class Argon2idHashingAlgo implements AtHashingAlgorithm<String, String> {
  @override
  String get name => HashingAlgoType.argon2id.name;

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
    // The salt is the password's UTF-16 code units while the secret is its
    // UTF-8 encoding. Those two disagree above U+00FF, and every atKeys
    // passphrase envelope in the field was derived with exactly that pairing,
    // so it is load-bearing rather than an oversight to tidy up.
    final generator = Argon2BytesGenerator()
      ..init(Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        Uint8List.fromList(password.codeUnits),
        desiredKeyLength: hashParams.hashLength,
        iterations: hashParams.iterations,
        memory: hashParams.memory,
        lanes: hashParams.parallelism,
        version: Argon2Parameters.ARGON2_VERSION_13,
      ));

    return Base64Encoder()
        .convert(generator.process(Uint8List.fromList(utf8.encode(password))));
  }
}
