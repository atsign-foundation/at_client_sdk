import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

import 'passkey_port.dart';

/// The `DOMException` names WebAuthn rejects with when a ceremony yields no
/// credential: cancelled, timed out, or no matching passkey.
const _noCredential = {'NotAllowedError', 'AbortError'};

/// Awaits [request]. A null result or a rejection named in [_noCredential]
/// throws [PasskeyCeremonyException]; any other rejection propagates.
Future<PublicKeyCredential> passkeyCeremony(
    JSPromise<Credential?> request) async {
  final Credential? credential;
  try {
    credential = await request.toDart;
  } catch (e) {
    final name = _errorName(e);
    if (_noCredential.contains(name)) throw PasskeyCeremonyException(name!);
    rethrow;
  }
  if (credential == null) {
    throw PasskeyCeremonyException('no credential returned');
  }
  return credential as PublicKeyCredential;
}

String? _errorName(Object error) {
  try {
    final name = (error as JSObject).getProperty<JSAny?>('name'.toJS);
    return name.isA<JSString>() ? (name as JSString).toDart : null;
  } on Object {
    return null;
  }
}
