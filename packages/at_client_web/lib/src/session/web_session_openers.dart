import 'keys_session_opener.dart';
import 'passkey_session_opener.dart';
import 'session_opener.dart';
import 'session_transport.dart';
import 'session_transport_options.dart';
import 'web_passkey_entry.dart';

/// The browser's [SessionOpener]: keys over `sessionTransport` and passkeys
/// through [passkeyLogin].
SessionOpener webSessionOpener() => RoutingSessionOpener(
    keys: KeysSessionOpener(transport: sessionTransport),
    passkey: PasskeySessionOpener(login: _webPasskeyLogin));

Future<OpenedSession> _webPasskeyLogin(PasskeySessionOptions o) async {
  final session = await passkeyLogin(
      atSign: o.atSign,
      app: o.namespace,
      rpId: o.rpId,
      rpName: o.rpName,
      transport: SessionTransportOptions(root: o.rootDomain));
  return OpenedSession(session.client, stop: session.stop);
}
