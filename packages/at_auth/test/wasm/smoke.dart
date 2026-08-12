// The entry point for the `dart compile wasm` step of the `wasm_compile` job in
// .github/workflows/at_libraries.yaml. It is compiled, never run — the only
// thing that matters is that compiling it reaches all of at_auth_web.dart, the
// barrel a web build imports.
//
// Everything here is deliberately *used*, so no part of the barrel can be
// tree-shaken away before the compiler resolves its imports.
//
// What this catches that dep_tree_test.dart cannot: `dart:ffi`, the one library
// dart2wasm rejects outright. `dart:io` it will NOT catch — dart2wasm accepts
// that and throws at runtime instead, which is the shakedown's job.
//
// Run it by hand with:
//   dart compile wasm test/wasm/smoke.dart -o /tmp/smoke.wasm
import 'package:at_auth/at_auth_web.dart';
import 'package:at_commons/at_commons.dart';

Future<void> main() async {
  final keys = AtKeys()..atsign = '@alice'.toAtsign();
  final io = InMemoryAtKeysIo();
  await io.write('@alice', keys);

  final session = AtAuthSession(
    atSign: '@alice',
    rootDomain: AtRootDomain('root.atsign.org', 64),
    atKeysIo: io,
  );
  final request = AtEnrollmentRequest(
    session: session,
    appName: 'wasm',
    deviceName: 'browser',
    namespaces: {'wasm': 'rw'},
    otp: '123456',
  );
  final atAuth = AtAuth.create();

  print([
    (await io.read('@alice')).atsign,
    session.atSign,
    request.appName,
    atAuth.progressStream.isBroadcast,
    AtKeysPassphraseEnvelopeCodec().isEnvelope(const {}),
    RegistrarService(registrarUrl: 'my.atsign.com', apiKey: 'x').registrarUrl,
  ].join(','));
}
