import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

/// A [RemoteSecondary] served from [remoteData], logging every wire operation
/// into [events] in call order:
///
///   `update:<key>[:rootlink|:chainlink]` · `delete:<key>` · `scan:<regex>` ·
///   `get:<key>` · `cmd:<head>`
///
/// Built for the startup-path instruments (the call-order recorder and the
/// no-AtKeysIo inertness pin), which observe `_fileConveyedKeysAndAnchor`
/// through its effects because its steps deliberately have no injection
/// seams. The atLookUp carries no enrollment id, so a client built on this is
/// fully privileged by construction.
///
/// Callers must `registerFallbackValue` a [VerbBuilder] fake in `setUpAll`.
MockRemoteSecondary buildRecordingRemote({
  required List<String> events,
  required Map<String, String> remoteData,
  required Map<String, Metadata> remoteMeta,
}) {
  final remote = MockRemoteSecondary();
  final lookUp = MockAtLookupImpl();
  when(() => remote.atLookUp).thenReturn(lookUp);
  when(() => lookUp.enrollmentId).thenReturn(null);
  when(() => remote.sync(any(), regex: any(named: 'regex')))
      .thenAnswer((_) async => null);

  String serveGet(String key) {
    final value = remoteData[key];
    if (value == null) {
      throw KeyNotFoundException('$key not found');
    }
    return 'data:${jsonEncode({
          'key': key,
          'data': value,
          'metaData': remoteMeta[key]?.toJson(),
        })}';
  }

  when(() => remote.executeVerb(any(), sync: any(named: 'sync')))
      .thenAnswer((inv) async {
    final builder = inv.positionalArguments[0];
    if (builder is UpdateVerbBuilder) {
      final key = builder.atKey.toString();
      final additional = builder.atKey.metadata.appMetadata?.additional;
      final tag = additional?.containsKey(PqSigningChain.rootLinkField) == true
          ? ':rootlink'
          : additional?.containsKey(PqSigningChain.linkField) == true
              ? ':chainlink'
              : '';
      events.add('update:$key$tag');
      remoteData[key] = builder.value;
      remoteMeta[key] = builder.atKey.metadata;
      return 'data:1';
    }
    if (builder is DeleteVerbBuilder) {
      final key = builder.atKey.toString();
      events.add('delete:$key');
      remoteData.remove(key);
      return 'data:1';
    }
    if (builder is ScanVerbBuilder) {
      final regex = builder.regex;
      events.add('scan:${regex ?? ''}');
      final re = regex == null ? null : RegExp(regex);
      final matches =
          remoteData.keys.where((k) => re == null || re.hasMatch(k)).toList();
      return 'data:${jsonEncode(matches)}';
    }
    if (builder is LLookupVerbBuilder) {
      final key = builder.buildKey();
      events.add('get:$key');
      return serveGet(key);
    }
    if (builder is PLookupVerbBuilder) {
      final atKey = builder.atKey;
      final ns = atKey.namespace;
      final key = 'public:${atKey.key}'
          '${ns == null || ns.isEmpty ? '' : '.$ns'}'
          '${atKey.sharedBy ?? ''}';
      events.add('get:$key');
      return serveGet(key);
    }
    throw StateError('buildRecordingRemote: unhandled ${builder.runtimeType}');
  });

  when(() => remote.executeCommand(any(), auth: any(named: 'auth')))
      .thenAnswer((inv) async {
    final command = inv.positionalArguments[0] as String;
    final head = command.split(RegExp(r'[\n{]')).first;
    events.add('cmd:$head');
    if (command.startsWith('enroll:list')) return 'data:{}';
    if (command.startsWith('enroll:listns')) return 'data:[]';
    if (command.startsWith('scan')) {
      final regexMatch = RegExp(r'scan (.*)\n?$').firstMatch(command);
      final re = regexMatch == null ? null : RegExp(regexMatch.group(1)!);
      final matches =
          remoteData.keys.where((k) => re == null || re.hasMatch(k)).toList();
      return 'data:${jsonEncode(matches)}';
    }
    throw StateError('buildRecordingRemote: unhandled command $command');
  });
  return remote;
}
