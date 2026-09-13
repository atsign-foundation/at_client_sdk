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

  final Map<String, dynamic> metaData;
}

/// A **real** [AtClientImpl] whose remote secondary serves [records], so
/// `get` runs the production pipeline — `GetRequestTransformer`, the verb, and
/// `GetResponseTransformer` with its decryption and provider routing.
///
/// `buildRemoteBackedMockClient` stubs `AtClient.get` outright, so use that
/// one when the client is a collaborator and this one when the read path
/// itself is under test.
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
    // NOTE: both `lookup` and `llookup` reach this fixture; matching on the
    // built command rather than the builder's type keeps them on one path.
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

  // NOTE: the lookup is answered but its `executeCommand` deliberately is not.
  // A real AtClientImpl runs its PQ startup, whose steps read the enrollment
  // id from here; measured, none of them reaches a command against this
  // fixture, so answering one would put words in the atServer's mouth that no
  // test asked for. If a step ever does reach it, an unstubbed member raises a
  // TypeError, which now logs at severe rather than passing for a condition.
  final atLookUp = MockAtLookupImpl();
  when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
  when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);

  // NOTE: the posture is named rather than defaulted because
  // `AtClientPreference.crypto` refuses a config registering the post-quantum
  // providers under a posture that configures none. A caller wanting the
  // provider-less stage builds its own preference.
  final preference = AtClientPreference(posture: PqPosture.pqReady)
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
