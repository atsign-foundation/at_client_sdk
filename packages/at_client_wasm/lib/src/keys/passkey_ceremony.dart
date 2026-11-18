import 'dart:js_interop';

import 'package:at_auth/passkey.dart' show PasskeyCeremonyException;
import 'package:web/web.dart';

import 'dom_exception_name.dart';

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
    final name = domExceptionName(e);
    if (_noCredential.contains(name)) throw PasskeyCeremonyException(name!);
    rethrow;
  }
  if (credential == null) {
    throw PasskeyCeremonyException('no credential returned');
  }
  return credential as PublicKeyCredential;
}
