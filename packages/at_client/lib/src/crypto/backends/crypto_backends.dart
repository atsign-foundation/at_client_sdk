/// The KEM and AEAD backends the post-quantum data path seals and opens with:
/// OpenSSL where a native build loads one that supports the algorithm, pure
/// Dart otherwise.
///
/// Chosen by a conditional export, so a web or wasm build never reaches
/// `dart:ffi`.
library;

export 'crypto_backends_dart.dart'
    if (dart.library.ffi) 'crypto_backends_native.dart';
