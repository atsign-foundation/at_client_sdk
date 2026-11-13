import 'package:at_auth/at_auth.dart';

import '../js/dev_session.dart';
import 'dev_session_options.dart';
import 'portal_session.dart';
import 'session_transport.dart';

/// Opens a [DevSession] on [keys] over the transport [options] selects.
Future<DevSession> openDevSession(
    DevSessionOptions options, AtKeys keys) async {
  final client = await portalSession(
      atSign: options.atSign,
      app: options.app,
      keys: keys,
      transport: sessionTransport(options),
      root: options.root);
  return AtClientDevSession(client, app: options.app);
}
