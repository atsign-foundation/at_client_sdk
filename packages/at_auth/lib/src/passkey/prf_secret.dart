import 'dart:typed_data';

/// The 32-byte PRF output of a passkey assertion.
///
/// Holds the buffer the client received; the holder wipes it once the
/// derivation has consumed it, after which [output] can no longer be read.
class PrfSecret {
  /// Holds [output] itself, not a copy.
  ///
  /// Throws [ArgumentError] when [output] is not 32 bytes or is all zeroes.
  PrfSecret(Uint8List output) : _output = output {
    if (output.length != 32) {
      throw ArgumentError('PRF output must be 32 bytes');
    }
    if (output.fold<int>(0, (any, b) => any | b) == 0) {
      throw ArgumentError('PRF output must not be all zeroes');
    }
  }

  final Uint8List _output;
  var _wiped = false;

  /// The 32 bytes of the PRF output.
  ///
  /// Throws [StateError] once [wipe] was called.
  Uint8List get output {
    if (_wiped) throw StateError('the PRF output was wiped');
    return _output;
  }

  /// Overwrites the output buffer with zeroes; reading [output] afterwards
  /// throws [StateError]. Only this buffer is cleared; copies made elsewhere
  /// are not tracked.
  void wipe() {
    _output.fillRange(0, _output.length, 0);
    _wiped = true;
  }
}
