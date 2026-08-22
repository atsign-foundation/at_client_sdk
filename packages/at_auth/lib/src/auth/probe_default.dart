/// The reachability probe for whichever platform this is compiled for.
///
/// Resolved at compile time, because neither implementation works everywhere:
///
/// - **Browser / WASM** gets [httpsProbe]. An atServer serves HTTP when the TLS
///   handshake negotiates `http/1.1` over ALPN, which a browser does as a
///   matter of course, so the GET is answered and the reply proves it is up.
/// - **`dart:io`** gets `secureSocketProbe`. `package:http`'s VM client does
///   **not** negotiate that ALPN protocol, so the same GET lands on the
///   atServer's own line protocol, which answers
///   `@error:AT0003 … invalid verb that does not match protocol spec` and
///   cannot be read as an HTTP response. A TLS handshake is what is available
///   there, and it is enough.
///
/// A caller wanting the other one, or something else entirely, sets
/// `probeSocket`.
export 'probe_default_web.dart'
    if (dart.library.io) 'probe_default_io.dart';
