import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';

/// What every [WireLookUp] a test's factory builds shares: how many were
/// dialled, what each was told, and how PKAM and the dial itself end.
class Wire {
  var dials = 0;
  var pkams = 0;
  final commands = <String>[];
  final finders = <SecondaryAddressFinder?>[];
  final lookUpsBuilt = <WireLookUp>[];

  /// What PKAM answers; false is a refusal.
  var pkamAccepted = true;

  /// When set, PKAM throws it instead of answering.
  Object? pkamThrows;

  /// What a `lookup:` or `llookup:` command answers; null answers nothing.
  String? lookupAnswer;

  /// Whether the connection itself fails: PKAM throws instead of answering.
  var connectFails = false;

  /// Whether closing or stopping a lookUp throws, as a client's stop does.
  var stopThrows = false;

  /// What the atServer answers a command with; null answers nothing.
  String? Function(String command)? answer;

  /// Called on each dial with its 1-based ordinal; a throw fails the dial.
  void Function(int dial)? onDial;

  /// Whether any command sent was an update: a write on the atServer.
  bool get wroteToServer => commands.any((c) => c.startsWith('update'));

  AtLookUpFactory get lookUps => ({
        required String atSign,
        required AtRootDomain rootDomain,
        required AtAuthenticator? authenticator,
        SecondaryAddressFinder? secondaryAddressFinder,
      }) {
        dials++;
        onDial?.call(dials);
        finders.add(secondaryAddressFinder);
        return WireLookUp(this)
          ..authenticator = authenticator
          ..also(lookUpsBuilt.add);
      };
}

class WireLookUp implements AtLookupMuxable {
  WireLookUp(this._wire);

  final Wire _wire;

  @override
  AtAuthenticator? authenticator;

  final inbound = StreamController<String>();
  var notificationStarts = 0;
  var commandsSent = 0;
  var closed = false;

  void also(void Function(WireLookUp) f) => f(this);

  @override
  Stream<String> get notifications => inbound.stream;

  @override
  Stream<bool> get notificationConnectionUp => const Stream.empty();

  @override
  Future<bool> pkamAuthenticate() async {
    _wire.pkams++;
    if (_wire.connectFails) throw StateError('connection refused');
    final thrown = _wire.pkamThrows;
    if (thrown != null) throw thrown;
    return _wire.pkamAccepted;
  }

  @override
  Future<String?> executeCommand(String command, {bool auth = false}) async {
    _wire.commands.add(command);
    commandsSent++;
    final isLookup =
        command.startsWith('lookup:') || command.startsWith('llookup:');
    return isLookup && _wire.lookupAnswer != null
        ? _wire.lookupAnswer
        : _wire.answer?.call(command);
  }

  @override
  Future<String?> executeVerb(VerbBuilder builder) async {
    final command = builder.buildCommand();
    _wire.commands.add(command);
    return _wire.answer?.call(command);
  }

  @override
  bool isConnectionAvailable() => true;

  @override
  Future<void> startNotifications(
      {String? regex,
      Future<int?> Function()? getLastNotificationTime,
      bool selfNotificationsEnabled = true}) async {
    notificationStarts++;
  }

  @override
  Future<void> stopNotifications() async {}

  @override
  Future<void> close() async {
    closed = true;
    if (_wire.stopThrows) throw StateError('close failed');
  }

  @override
  Future<void> stop() async {
    if (_wire.stopThrows) throw StateError('stop failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}
