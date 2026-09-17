/// The `dart:io` half of at_auth: everything that needs a filesystem, a raw
/// socket, or the `dart:io` HTTP stack.
///
/// `package:at_auth/at_auth.dart` holds the parts that do not — key material,
/// the stores' interfaces, the auth and enrollment flows — so that a client
/// compiled to WASM can authenticate. Anything a browser cannot do lives here
/// instead, and importing this barrel is the statement that you are on a
/// platform that can.
///
/// A `dart:io` program typically wants both of these, and neither is applied
/// for you:
///
/// ```dart
/// import 'package:at_auth/at_auth.dart';
/// import 'package:at_auth/at_auth_io.dart';
/// import 'package:at_lookup/at_lookup_io.dart';
///
/// retrofitSerializer = fileRetrofitSerializer;      // lock the keyfile
/// final atLookUp = secureSocketLookUps()(
///     atSign: atSign, rootDomain: rootDomain, authenticator: null);
/// final enrollmentId = await activateAtSign(
///     atSign: atSign,
///     cramSecret: secret,
///     keys: FileAtKeysIo(),                         // write keys to disk
///     signingAlgo: SigningAlgoType.rsa2048,
///     atLookUp: atLookUp,
///     awaitProvisioning: true);
/// await atLookUp.close();
/// ```
///
/// Each has a working default without this barrel — no serialiser and no
/// keyfile — so a WASM build needs neither, and a `dart:io` build opts in to
/// the behaviour it wants.
library;

export 'src/enroll/file_retrofit_serializer.dart';
export 'src/keys/io/file_io.dart';
export 'src/registrar/registrar_io_client.dart';
