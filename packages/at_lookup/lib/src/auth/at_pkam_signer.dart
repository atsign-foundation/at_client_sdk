import 'dart:async';
import 'dart:typed_data';

// SigningAlgoType / HashingAlgoType are plain (non-deprecated) enums.
import 'package:at_chops/at_chops.dart' show SigningAlgoType, HashingAlgoType;

/// Strategy for signing the PKAM `from` challenge during authentication.
///
/// [AtLookUp] drives the PKAM handshake but does not own any key material or
/// know which signing algorithm is in play. The consumer (at_auth) implements
/// this strategy — holding the private key and choosing RSA vs ML-DSA — and
/// hands it to at_lookup via `AtLookUp.pkamSigner`.
abstract interface class AtPkamSigner {
  /// Signs [challenge] and returns the raw signature bytes. at_lookup
  /// base64-encodes the result onto the pkam verb.
  FutureOr<Uint8List> sign(Uint8List challenge);

  /// The signing algorithm, stamped onto the pkam verb wire form.
  SigningAlgoType get signingAlgo;

  /// The hashing algorithm, stamped onto the pkam verb wire form.
  HashingAlgoType get hashingAlgo;
}
