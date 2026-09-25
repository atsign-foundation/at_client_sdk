/// Throws [StateError] unless [actual] equals [expected].
///
/// Shared by every PQ backend (ML-KEM-768, ML-DSA-65, X-Wing — FFI and
/// pure-Dart) to check a backend's own output against its FIPS 203/204/
/// X-Wing-draft fixed size. A mismatch here is a backend bug (wrong OpenSSL
/// version, algorithm mix-up), not caller input, so it must throw
/// unconditionally rather than via `assert()` — asserts strip in release
/// builds, letting a wrong-size output propagate into buffers sized for the
/// expected length.
void checkOutputLength(int actual, int expected,
    {required String operation, required String label}) {
  if (actual != expected) {
    throw StateError(
        '$operation produced a $actual-byte $label, expected $expected');
  }
}
