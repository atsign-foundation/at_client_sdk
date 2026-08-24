import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

/// A record as the atServer serves it: the value bytes and the raw `metaData`
/// map, exactly as they travel.
class WireRecord {
  WireRecord(this.value, this.metaData);

  /// The stored value — ciphertext for an encrypted record.
  final String value;

  /// The `metaData` object the atServer returns, as a raw map so a test pins
  /// the bytes rather than whatever a `Metadata` happens to serialise to.
  final Map<String, dynamic> metaData;
}

/// A **real** [AtClientImpl] whose remote secondary serves [records], so
/// `get` runs the production pipeline — `GetRequestTransformer`, the verb, and
/// `GetResponseTransformer` with its decryption and provider routing.
///
/// ## Why this exists
///
/// The other fixture, `buildRemoteBackedMockClient`, stubs `AtClient.get`
/// outright. That is right for code which merely *calls* get, and it made
/// `GetResponseTransformer` unreachable from every unit test: 1543 of them run
/// without the response path ever executing. A wrong-value read measured
/// against a live atServer in 2026-08 could not be pinned by any unit test for
/// exactly that reason.
///
/// So the two are not alternatives. Use the mock when the client is a
/// collaborator; use this when the read path itself is what is under test.
///
/// [records] is keyed by the full at-key string as `AtKey.toString()` renders
/// it, and is mutable — a test can add a record mid-run to model one arriving.
/// A key that is absent answers `data:null`, which is what a real lookup of a
/// missing record returns; it must not silently read as an empty value.
///
/// Callers must `registerFallbackValue(FakeLookupVerbBuilder())` in `setUpAll`.
Future<AtClient> buildPipelineBackedClient({
  required String atSign,
  required String namespace,
  required Map<String, WireRecord> records,
  required String storagePath,
  CryptoConfig? crypto,
  String? enrollmentId,
  List<String>? lookupLog,
}) async {
  final remoteSecondary = MockRemoteSecondary();

  when(() => remoteSecondary.executeVerb(any(), sync: any(named: 'sync')))
      .thenAnswer((invocation) async {
    final builder = invocation.positionalArguments[0];
    // Both verbs reach this fixture: a shared record is fetched with `lookup`,
    // a self or already-local one with `llookup`. Keying off the built command
    // rather than the builder's type keeps the two on one path.
    final command = builder.buildCommand() as String;
    lookupLog?.add(command.trim());
    final match = records.entries.firstWhere(
      (entry) => command.contains(entry.key),
      orElse: () => MapEntry('', WireRecord('', const {})),
    );
    if (match.key.isEmpty) return 'data:null';
    return 'data:${jsonEncode({
          'key': match.key,
          'data': match.value.value,
          'metaData': match.value.metaData,
        })}';
  });

  final preference = AtClientPreference()
    ..hiveStoragePath = storagePath
    ..commitLogPath = '$storagePath/commit'
    ..isLocalStoreRequired = true;
  if (crypto != null) preference.crypto = crypto;

  return AtClientImpl.create(
    atSign,
    namespace,
    preference,
    remoteSecondary: remoteSecondary,
    enrollmentId: enrollmentId,
  );
}
