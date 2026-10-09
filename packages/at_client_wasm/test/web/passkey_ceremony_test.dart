@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:at_client_wasm/src/keys/passkey_ceremony.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

@JS('Promise.reject')
external JSPromise<Credential?> _reject(JSAny? reason);

@JS('Promise.resolve')
external JSPromise<Credential?> _resolve(JSAny? value);

void main() {
  for (final name in ['NotAllowedError', 'AbortError']) {
    test('a $name rejection is a PasskeyCeremonyException', () async {
      await expectLater(
          passkeyCeremony(_reject(DOMException('x', name))),
          throwsA(isA<PasskeyCeremonyException>()
              .having((e) => e.message, 'message', name)));
    });
  }

  for (final name in ['SecurityError', 'InvalidStateError']) {
    test('a $name rejection propagates', () async {
      await expectLater(passkeyCeremony(_reject(DOMException('x', name))),
          throwsA(isNot(isA<PasskeyCeremonyException>())));
    });
  }

  test('a non-object rejection propagates', () async {
    await expectLater(passkeyCeremony(_reject('boom'.toJS)),
        throwsA(isNot(isA<PasskeyCeremonyException>())));
  });

  test('a null credential is a PasskeyCeremonyException', () async {
    await expectLater(passkeyCeremony(_resolve(null)),
        throwsA(isA<PasskeyCeremonyException>()));
  });
}
