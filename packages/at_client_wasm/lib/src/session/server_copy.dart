import 'dart:convert';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';

/// Reads the server copy of an atSign's key envelope for an app.
abstract interface class ServerCopyReader {
  Future<Uint8List?> fetch(String atSign, String app);
}

/// Reads and writes the server copy of an atSign's key envelope for an app.
abstract interface class ServerCopy implements ServerCopyReader {
  Future<void> put(String atSign, String app, Uint8List envelope);
}

/// The atProtocol key the envelope is published under, without the `public:` scope:
/// `_atkeys.<app>@<atsign>` (atSign normalised with a leading @). ArgumentError when [app]
/// is empty or contains ':', '@', whitespace or '.'-leading/trailing.
String atKeysRecordKey(String atSign, String app) {
  if (app.isEmpty ||
      app.contains(':') ||
      app.contains('@') ||
      app.contains(RegExp(r'\s')) ||
      app.startsWith('.') ||
      app.endsWith('.')) {
    throw ArgumentError.value(app, 'app', 'invalid app namespace');
  }
  return '_atkeys.$app${Atsign(atSign)}';
}

/// `update:public:<atKeysRecordKey> <envelope as UTF-8 text>\n`
String updateCommand(String atSign, String app, Uint8List envelope) {
  final recordKey = atKeysRecordKey(atSign, app);
  final envelopeText = utf8.decode(envelope);
  if (envelopeText.contains('\n')) {
    throw StateError('Envelope must not contain newlines');
  }
  return 'update:public:$recordKey $envelopeText\n';
}
