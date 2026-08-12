// The entry point for the `dart compile wasm` gate in
// ../wasm_compile_test.dart. It is not a test and is never executed — the only
// thing that matters is that compiling it reaches at_auth's whole main barrel.
//
// Everything here is deliberately *used*, so no part of the barrel can be
// tree-shaken away before the compiler resolves its imports.
import 'package:at_auth/at_auth.dart';
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
