import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo;
import 'package:at_commons/at_commons.dart' show AtRootDomain;
import 'package:at_lookup/at_lookup.dart';
import 'package:uuid/uuid.dart';

import '../test_utils/fake_at_server.dart' show FakeAtServerSocket;

/// One atSign's atServer over in-memory sockets, with every connection run by
/// the production lookup: it answers `from:` with a fresh challenge, accepts
/// a `pkam:` only when its signature over that challenge verifies under the
/// APKAM public key of the enrollment it names, keeps what `update:` stores
/// and answers `llookup:`, `lookup:` and `delete:` from it.
class PasskeyAtServer implements AtTransportFactory {
  PasskeyAtServer(this.atSign);

  /// The atSign this atServer serves.
  final String atSign;

  final records = <String, String>{};

  /// Whether a create of an immutable record is refused while an earlier
  /// create of it is within its ttl, as an atServer refuses it.
  var immutableHolds = false;
  final _immutableUntil = <String, DateTime>{};

  /// Makes the next @keys document update wait, before it is stored, until
  /// another connection sends a command about a @keys document or its lock.
  var holdDocumentPut = false;
  int? _heldOn;
  Completer<void>? _held;

  /// The APKAM public key of each enrollment.
  final apkamKeys = <String, String>{};

  /// Every command, as `<connection>: <command>`, connections counted from 0.
  final commands = <String>[];
  final sockets = <FakeAtServerSocket>[];
  final _challenges = <FakeAtServerSocket, String>{};
  final _authenticated = <FakeAtServerSocket>{};

  /// Whether the CRAM secret is still live, so an activation can use it.
  var cramLive = true;

  final SecondaryAddressFinder finder = _Here();

  AtLookUpFactory get lookUps => ({
        required String atSign,
        required AtRootDomain rootDomain,
        required AtAuthenticator? authenticator,
        SecondaryAddressFinder? secondaryAddressFinder,
      }) =>
          AtLookUp.withSecureSocket(
              atSign: atSign,
              rootDomain: rootDomain,
              authenticator: authenticator,
              secondaryAddressFinder: finder,
              transport: AtLookupTransport(transportFactory: this));

  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    final socket = FakeAtServerSocket(_answer);
    sockets.add(socket);
    return socket;
  }

  /// The commands connection [connection] received, in order.
  List<String> on(int connection) => [
        for (final c in commands)
          if (c.startsWith('$connection: ')) c.substring('$connection: '.length)
      ];

  void _answer(FakeAtServerSocket socket, String command) {
    final line = command.trimRight();
    final connection = sockets.indexOf(socket);
    commands.add('$connection: $line');
    final held = _held;
    if (held != null && connection != _heldOn && line.contains('atkeys')) {
      _held = null;
      held.complete();
    }
    if (holdDocumentPut && line.startsWith('update:atkeys.')) {
      holdDocumentPut = false;
      _heldOn = connection;
      final hold = _held = Completer<void>();
      unawaited(
          hold.future.then((_) => socket.serverSends(_reply(socket, line))));
      return;
    }
    unawaited(socket.serverSends(_reply(socket, line)));
  }

  String _reply(FakeAtServerSocket socket, String line) {
    final prompt = _authenticated.contains(socket) ? '\n$atSign@' : '\n@';
    if (line.startsWith('from:')) {
      final challenge = '_${const Uuid().v4()}$atSign:${const Uuid().v4()}';
      _challenges[socket] = challenge;
      return 'data:$challenge$prompt';
    }
    if (line.startsWith('pkam:')) {
      if (!_verifies(socket, line)) {
        return 'error:{"errorCode":"AT0401","errorDescription":"pkam '
            'authentication failed"}$prompt';
      }
      _authenticated.add(socket);
      return 'data:success\n$atSign@';
    }
    if (line.startsWith('update:')) {
      final body = line.substring('update:'.length);
      final split = body.indexOf(' ');
      final spec = body.substring(0, split);
      final key = _keyOf(spec);
      if (immutableHolds && spec.contains(':immutable:true:')) {
        final until = _immutableUntil[key];
        final now = DateTime.now();
        if (until != null && now.isBefore(until)) {
          return 'error:{"errorCode":"AT0032","errorDescription":"Immutable '
              'records may not be updated"}$prompt';
        }
        final ttl = int.parse(RegExp(r'ttl:(\d+):').firstMatch(spec)![1]!);
        _immutableUntil[key] = now.add(Duration(milliseconds: ttl));
      }
      records[key] = body.substring(split + 1);
      return 'data:1$prompt';
    }
    if (line.startsWith('llookup:')) {
      return _value(records[line.substring('llookup:'.length)], prompt);
    }
    if (line.startsWith('lookup:')) {
      return _value(
          records['public:${line.substring('lookup:'.length)}'], prompt);
    }
    if (line.startsWith('delete:')) {
      if (line == 'delete:privatekey:at_secret') cramLive = false;
      records.remove(_keyOf(line.substring('delete:'.length)));
      return 'data:1$prompt';
    }
    if (line.startsWith('enroll:list')) return 'data:{}$prompt';
    if (line == 'stats:3') {
      return 'data:[{"id":"3","name":"lastCommitID","value":"-1"}]$prompt';
    }
    return 'data:null$prompt';
  }

  /// The key an `update:` or `delete:` names, without the metadata before it.
  static String _keyOf(String spec) {
    final public = spec.indexOf('public:');
    return public >= 0 ? spec.substring(public) : spec.split(':').last;
  }

  static String _value(String? value, String prompt) => value == null
      ? 'error:{"errorCode":"AT0015","errorDescription":"key not found"}'
          '$prompt'
      : 'data:$value$prompt';

  bool _verifies(FakeAtServerSocket socket, String line) {
    final enrollment =
        RegExp(r'enrollmentId:([^:]+):').firstMatch(line)?.group(1);
    final publicKey = apkamKeys[enrollment];
    final challenge = _challenges[socket];
    if (publicKey == null || challenge == null) return false;
    return MlDsa65PureDartAlgo.verifyBytesSync(
        Uint8List.fromList(utf8.encode(challenge)),
        signature: base64Decode(line.split(':').last),
        publicKey: base64Decode(publicKey));
  }
}

class _Here extends SecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('127.0.0.1', 6464);
}
