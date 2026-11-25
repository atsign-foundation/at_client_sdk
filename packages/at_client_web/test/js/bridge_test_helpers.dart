import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_client/at_client.dart'
    show AtClient, AtConnection, AtConnectionState;
import 'package:at_client/passkey.dart' show PasskeySession;
import 'package:at_client_web/src/session/session_options.dart';
import 'package:at_client_web/src/session/session_transport_options.dart';
import 'package:test/fake.dart' show Fake;
import 'package:test/test.dart' show fail;

/// What a promise settled with: a value or a rejection.
sealed class Settled {}

class Resolved extends Settled {
  Resolved(this.value);
  final JSAny? value;
}

class Rejected extends Settled {
  Rejected(this.reason);
  final JSAny? reason;

  String get code => (reason! as JSObject)['code'].dartify()! as String;
  String get message => (reason! as JSObject)['message'].dartify()! as String;
  Object? field(String name) => (reason! as JSObject)[name].dartify();
}

Future<Settled> settle(JSAny? promise) {
  final done = Completer<Settled>();
  (promise! as JSObject).callMethod(
      'then'.toJS,
      ((JSAny? v) => done.complete(Resolved(v))).toJS,
      ((JSAny? r) => done.complete(Rejected(r))).toJS);
  return done.future;
}

Future<JSAny?> resolved(JSAny? promise) async {
  final settled = await settle(promise);
  if (settled is Rejected) {
    fail('rejected with ${settled.code}: ${settled.message}');
  }
  return (settled as Resolved).value;
}

Future<Rejected> rejected(JSAny? promise) async {
  final settled = await settle(promise);
  if (settled is Resolved) fail('resolved with ${settled.value}');
  return settled as Rejected;
}

JSObject jsObject(Map<String, Object?> map) => map.jsify()! as JSObject;

JSAny? invoke(JSObject target, String name, [List<JSAny?> args = const []]) =>
    args.isEmpty
        ? target.callMethod(name.toJS)
        : target.callMethodVarArgs(name.toJS, args);

/// A client whose session builds.
class PasskeyClient extends Fake implements AtClient {
  @override
  final AtConnection connection = AtConnection(
      atSign: '@alice', attempt: (_) async => AtConnectionState.online());
}

/// A passkey session whose [stop] is recorded and can be held open.
class GatedPasskeySession extends Fake implements PasskeySession {
  GatedPasskeySession(this.client);

  @override
  final AtClient client;

  var stops = 0;
  Completer<void>? stopGate;

  @override
  Future<void> stop() async {
    stops++;
    if (stopGate case final gate?) await gate.future;
  }
}

/// Records the options and transport the passkey arm hands the login, and
/// opens [session].
class RecordingPasskeyLogin {
  RecordingPasskeyLogin(this.session);

  final GatedPasskeySession session;
  final seen = <PasskeySessionOptions>[];
  final transports = <SessionTransportOptions>[];

  Future<PasskeySession> call(
      PasskeySessionOptions options, SessionTransportOptions transport) async {
    seen.add(options);
    transports.add(transport);
    return session;
  }
}
