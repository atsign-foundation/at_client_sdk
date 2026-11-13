import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

import 'prf_support.dart';

const _missKey = 'at_client_wasm:prf-miss-at';

/// A [PrfEnvironment] over `PublicKeyCredential.getClientCapabilities()` and
/// `localStorage`.
class WebPrfEnvironment implements PrfEnvironment {
  @override
  Future<bool?> clientCapabilityPrf() async {
    try {
      final credential =
          globalContext.getProperty<JSAny?>('PublicKeyCredential'.toJS);
      if (!credential.isA<JSObject>()) return null;
      final api = (credential as JSObject)
          .getProperty<JSAny?>('getClientCapabilities'.toJS);
      if (!api.isA<JSFunction>()) return null;
      final capabilities = await (credential
              .callMethod<JSPromise<JSObject?>>('getClientCapabilities'.toJS))
          .toDart;
      final prf = capabilities?.getProperty<JSAny?>('extension:prf'.toJS);
      return prf.isA<JSBoolean>() ? (prf as JSBoolean).toDart : null;
    } on Object {
      return null;
    }
  }

  @override
  DateTime? missRecordedAt() {
    try {
      final millis = int.tryParse(window.localStorage.getItem(_missKey) ?? '');
      return millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    } on Object {
      return null;
    }
  }

  @override
  void recordMiss(DateTime at) {
    try {
      window.localStorage
          .setItem(_missKey, at.millisecondsSinceEpoch.toString());
    } on Object {
      // Without storage the miss is not remembered.
    }
  }

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Whether this browser can evaluate passkey PRF, as [PrfSupport.supported]
/// decides it.
Future<bool> prfSupported() => PrfSupport(WebPrfEnvironment()).supported();
