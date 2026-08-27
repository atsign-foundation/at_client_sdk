/// The `dart:io` half of at_auth: everything that needs a filesystem, a raw
/// socket, or the `dart:io` HTTP stack.
///
/// `package:at_auth/at_auth.dart` holds the parts that do not — key material,
/// the stores' interfaces, the auth and enrollment flows — so that a client
/// compiled to WASM can authenticate. Anything a browser cannot do lives here
/// instead, and importing this barrel is the statement that you are on a
/// platform that can.
///
/// A `dart:io` program typically wants all three of these, and none of them is
/// applied for you:
///
/// ```dart
/// import 'package:at_auth/at_auth.dart';
/// import 'package:at_auth/at_auth_io.dart';
///
/// retrofitSerializer = fileRetrofitSerializer;      // lock the keyfile
/// final request = AtAuthRequest(atSign,
///     atKeysIo: FileAtKeysIo(),                     // read keys from disk
///     probeSocket: secureSocketProbe);              // TLS-handshake probe
/// ```
///
/// Each has a working default without this barrel — no serialiser, no keyfile,
/// and an HTTPS probe — so a WASM build needs none of them, and a `dart:io`
/// build opts in to the behaviour it wants.
library;

export 'src/auth/socket_probe_io.dart';
export 'src/enroll/file_retrofit_serializer.dart';
export 'src/keys/io/file_io.dart';
export 'src/registrar/registrar_io_client.dart';
