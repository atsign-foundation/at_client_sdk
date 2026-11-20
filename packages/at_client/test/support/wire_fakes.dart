import 'dart:async';
import 'dart:collection';

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

  /// Whether the authenticator succeeds. False is an authenticator reporting
  /// failure, which PKAM returns as false.
  var pkamAccepted = true;

  /// Whether PKAM runs the authenticator the lookUp was built with, as a real
  /// connection does: it reads the keys, answers `from:` with a challenge,
  /// records each `pkam:` command in [pkamCommands] and answers it with
  /// [pkamReply]. Off, PKAM never calls it.
  var runsAuthenticator = false;

  /// Every `pkam:` command an authenticator sent, in order.
  final pkamCommands = <String>[];

  /// What a `pkam:` an authenticator sends is answered with.
  var pkamReply = 'data:success';

  /// What a `lookup:` or `llookup:` command answers; null answers nothing.
  /// An `error:<code>-<text>` answer is thrown as the [AtLookUpException] a
  /// real `AtLookupImpl` throws for it, as one never returns an `error:`
  /// reply.
  String? lookupAnswer;

  /// One entry per PKAM, taken in order: that PKAM waits for it, then goes by
  /// its value as by [pkamAccepted]. Once empty, PKAM goes by [pkamAccepted]
  /// at once.
  final pkamScript = Queue<Completer<bool>>();

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

  static final _errorReply = RegExp(r'^error:(AT\d{4})[-:]?(.*)$');

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

  /// Returns what the authenticator reports: an authenticator that reports
  /// failure is a false, which [AtLookUp.pkamAuthenticate]'s contract permits.
  @override
  Future<bool> pkamAuthenticate() async {
    _wire.pkams++;
    if (_wire.connectFails) throw StateError('connection refused');
    final run = authenticator;
    if (_wire.runsAuthenticator && run != null) {
      return run(_WireExecutor(_wire));
    }
    if (_wire.pkamScript.isNotEmpty) {
      return _wire.pkamScript.removeFirst().future;
    }
    return _wire.pkamAccepted;
  }

  @override
  Future<String?> executeCommand(String command, {bool auth = false}) async {
    _wire.commands.add(command);
    commandsSent++;
    final isLookup =
        command.startsWith('lookup:') || command.startsWith('llookup:');
    final lookupAnswer = _wire.lookupAnswer;
    if (!isLookup || lookupAnswer == null) return _wire.answer?.call(command);
    final error = _errorReply.firstMatch(lookupAnswer);
    if (error != null) throw AtLookUpException(error[1]!, error[2]!);
    return lookupAnswer;
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

/// The connection an authenticator sees: answers `from:` with a challenge and
/// every `pkam:` with [Wire.pkamReply], recording it.
class _WireExecutor implements AtCommandExecutor {
  _WireExecutor(this._wire);

  final Wire _wire;

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    if (command.startsWith('from:')) {
      final atSign = command.substring(5).split(RegExp('[:\\n]')).first.trim();
      final named = atSign.startsWith('@') ? atSign : '@$atSign';
      return 'data:_123e4567-e89b-12d3-a456-426614174000$named:'
          '123e4567-e89b-12d3-a456-426614174000';
    }
    if (command.startsWith('pkam:')) {
      _wire.pkamCommands.add(command);
      return _wire.pkamReply;
    }
    return 'error:unexpected $command';
  }
}
