/// Throws [StateError] unless [actual] equals [expected].
///
/// Checks a length a backend produced or reported against the length its
/// algorithm defines for that input. A mismatch here is a backend bug (wrong
/// OpenSSL version, algorithm mix-up), not caller input, so it must throw
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
