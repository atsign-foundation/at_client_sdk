import 'package:at_client_wasm/at_client_wasm_web.dart';

/// The compile target `test/web/compile_test.dart` builds with dart2js and
/// dart2wasm: it pulls in the whole slim client, `InMemoryAtClientStorage`
/// and the passkey entry points among it.
Future<void> main() async {
  final options = DevSessionOptions(atSign: '@alice', app: 'wavi');
  print(sessionTransport(options).finder);
  print([onboardNewAtSign, passkeyLogin, prfSupported].length);
}
