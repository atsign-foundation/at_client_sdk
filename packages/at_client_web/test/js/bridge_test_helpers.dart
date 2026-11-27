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

/// A JS object holding [defined] plus each of [undefinedKeys] as a member
/// whose value is JS `undefined`. Dart cannot write `undefined` under
/// dart2wasm, so the members are built JS-side: `Object.fromEntries` over
/// `[key, undefined]` pairs, each pair an `Array.from({length: 2})` with its
/// first element replaced by the key.
JSObject withUndefinedMembers(
    Map<String, Object?> defined, List<String> undefinedKeys) {
  final array = globalContext['Array']! as JSObject;
  final pairs = <JSAny?>[
    for (final key in undefinedKeys)
      (array.callMethod('from'.toJS, jsObject({'length': 2}))! as JSObject)
        ..setProperty(0.toJS, key.toJS)
  ];
  final object = (globalContext['Object']! as JSObject)
      .callMethod('fromEntries'.toJS, pairs.toJS)! as JSObject;
  defined.forEach((key, value) => object[key] = value.jsify());
  return object;
}

/// An array of [length] elements all JS `undefined`, with each entry of
/// [defined] written at its index, so a hole the caller fills sits beside
/// undefined elements.
JSArray<JSAny?> arrayWithUndefined(int length, Map<int, Object?> defined) {
  final list = (globalContext['Array']! as JSObject)
      .callMethod('from'.toJS, jsObject({'length': length}))! as JSObject;
  defined
      .forEach((index, value) => list.setProperty(index.toJS, value.jsify()));
  return list as JSArray<JSAny?>;
}

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
/// opens [session] on [lock], the open lock the bridge hands to the session.
class RecordingPasskeyLogin {
  RecordingPasskeyLogin(this.session, {this.lock = 'the passkey open lock'});

  final GatedPasskeySession session;
  final String lock;
  final seen = <PasskeySessionOptions>[];
  final transports = <SessionTransportOptions>[];

  Future<(PasskeySession, String)> call(
      PasskeySessionOptions options, SessionTransportOptions transport) async {
    seen.add(options);
    transports.add(transport);
    return (session, lock);
  }
}
