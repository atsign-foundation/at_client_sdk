import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

class _Record {
  _Record(this.value, this.metadata, this.protocolMetadata);
  final String value;
  final Metadata metadata;

  /// The metadata as the update command carried it, keyed by protocol name.
  final Map<String, String> protocolMetadata;
}

class _CommitEntry {
  _CommitEntry(this.atKey, this.operation, this.commitId);
  final String atKey;
  final String operation;
  final int commitId;
}

/// One atServer's keystore and commit log behind a [MockRemoteSecondary], so
/// every client handed [remote] sees the others' writes.
///
/// Writes are parsed with the at_commons verb builders and stored exactly as
/// sent; `update`, `delete` and `batch:` commit, `llookup:all`, `stats:3` and
/// `sync:from` read. Anything else throws [UnimplementedError].
///
/// Callers must `registerFallbackValue` a [VerbBuilder] fake in `setUpAll`.
/// Answers `executeVerb` by override rather than by stub: dart2wasm passes the
/// defaulted `sync` / `cameFromServer` in every invocation, which mocktail's
/// named matchers reject.
class _VerbRemote extends MockRemoteSecondary {
  _VerbRemote(this._answer);
  final String Function(VerbBuilder) _answer;

  @override
  Future<String> executeVerb(VerbBuilder builder,
          {sync = false, bool cameFromServer = false}) async =>
      _answer(builder);
}

class StatefulFakeServer {
  StatefulFakeServer(this.atSign) {
    remote = _VerbRemote(_verb);
    when(() => remote.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((inv) async =>
            _command((inv.positionalArguments[0] as String).trim()));
    when(() => remote.closeConnection()).thenAnswer((_) async {});
  }

  final String atSign;
  late final MockRemoteSecondary remote;
  final Map<String, _Record> _records = {};
  final List<_CommitEntry> _log = [];

  /// The stored value of [atKey], exactly as the writing client sent it.
  String? storedValue(String atKey) => _records[atKey]?.value;

  int get lastCommitId => _log.isEmpty ? -1 : _log.last.commitId;

  String _command(String command) {
    if (command.startsWith('batch:')) {
      final requests = jsonDecode(command.substring('batch:'.length)) as List;
      return 'data:${jsonEncode([
            for (final r in requests.cast<Map>())
              {
                'id': r['id'],
                'response': {
                  'data': _command((r['command'] as String).trim())
                      .replaceFirst('data:', '')
                },
              }
          ])}';
    }
    if (command.startsWith('delete:')) {
      final key = DeleteVerbBuilder.getBuilder(command).atKey.toString();
      _records.remove(key);
      return 'data:${_commit(key, '-')}';
    }
    if (command.startsWith('update:meta:')) {
      throw UnimplementedError('StatefulFakeServer: $command');
    }
    if (command.startsWith('update')) {
      final builder = UpdateVerbBuilder.getBuilder(command) ??
          (throw ArgumentError.value(command, 'command', 'not an update'));
      final params = VerbUtil.getVerbParam(VerbSyntax.update, command)!;
      const notMetadata = {
        'atKey', 'atSign', 'forAtSign', 'publicScope', 'value', 'noCommit', //
        'json',
      };
      final key = builder.atKey.toString();
      _records[key] = _Record('${builder.value}', builder.atKey.metadata, {
        for (final e in params.entries)
          if (e.value != null && !notMetadata.contains(e.key)) e.key: e.value!,
      });
      return 'data:${_commit(key, '+')}';
    }
    throw UnimplementedError('StatefulFakeServer: $command');
  }

  int _commit(String atKey, String operation) {
    final id = lastCommitId + 1;
    _log.add(_CommitEntry(atKey, operation, id));
    return id;
  }

  String _verb(Object builder) {
    if (builder is StatsVerbBuilder) {
      return 'data:${jsonEncode([
            {'id': '3', 'name': 'lastCommitID', 'value': '$lastCommitId'}
          ])}';
    }
    if (builder is SyncVerbBuilder) {
      final latest = <String, _CommitEntry>{
        for (final e in _log)
          if (e.commitId > builder.commitId) e.atKey: e,
      };
      final entries = latest.values.toList()
        ..sort((a, b) => a.commitId.compareTo(b.commitId));
      return 'data:${jsonEncode([
            for (final e in entries.take(builder.limit))
              {
                'atKey': e.atKey,
                'operation': e.operation,
                'commitId': e.commitId,
                if (e.operation == '+') ...{
                  'value': _records[e.atKey]!.value,
                  'metadata': _records[e.atKey]!.protocolMetadata,
                },
              }
          ])}';
    }
    if (builder is LLookupVerbBuilder) {
      final key = builder.atKey.toString();
      final record = _records[key] ??
          (throw KeyNotFoundException('$key does not exist in keystore'));
      return 'data:${jsonEncode((AtData()
        ..data = record.value
        ..metaData = AtMetaData.fromCommonsMetadata(record.metadata, atSign)).toJson())}';
    }
    throw UnimplementedError('StatefulFakeServer: ${builder.runtimeType}');
  }
}
