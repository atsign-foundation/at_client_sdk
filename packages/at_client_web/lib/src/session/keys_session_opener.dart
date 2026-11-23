import 'package:at_client/at_client.dart';

import 'portal_session.dart';
import 'session_opener.dart';
import 'session_transport_options.dart';

/// Opens a session on a `.atKeys` document, with in-memory storage.
class KeysSessionOpener implements SessionOpener {
  /// [transport] builds the transport for the options' root; the browser's is
  /// `sessionTransport`. [open] is [portalSession] unless a test gives its
  /// own.
  KeysSessionOpener(
      {required SessionTransport Function(SessionTransportOptions) transport,
      Future<AtClient> Function({
        required String atSign,
        required String app,
        required AtKeys keys,
        required SessionTransport transport,
      }) open = _portal})
      : _transport = transport,
        _open = open;

  final SessionTransport Function(SessionTransportOptions) _transport;

  /// Opens the client for [AtKeys] and the transport [SessionTransportOptions]
  /// describes.
  final Future<AtClient> Function({
    required String atSign,
    required String app,
    required AtKeys keys,
    required SessionTransport transport,
  }) _open;

  static Future<AtClient> _portal(
          {required String atSign,
          required String app,
          required AtKeys keys,
          required SessionTransport transport}) =>
      portalSession(atSign: atSign, app: app, keys: keys, transport: transport);

  @override
  Future<OpenedSession> open(SessionOptions options) async {
    if (options is! KeysSessionOptions) {
      throw ArgumentError('is not a keys session', 'options');
    }
    final client = await _open(
        atSign: options.atSign,
        app: options.namespace,
        keys: options.keys,
        transport:
            _transport(SessionTransportOptions(root: options.rootDomain)));
    return OpenedSession(client);
  }
}
