import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

/// A mock [AtClient] whose puts and gets go through [remoteData], so several
/// clients of the same atSign share one view of the atServer.
///
/// That sharing is the point rather than a convenience: the substrate's
/// verification path has one client publish its `_apsk` and another read it
/// back, and a fixture giving each client its own store would let a signature
/// check pass against a key nobody else could see.
///
/// ## Routing
///
/// By default one map backs both stores, so the fixture **cannot tell a
/// local-first write from a remote-first one** and a test that cares about
/// routing has to assert the routing directly rather than the result. That
/// blind spot is how the `__ssenv` wake-up ordering bug survived, and how the
/// nskey mint read local storage — where a sibling's publication is absent
/// until sync catches up — while every unit test stayed green.
///
/// Pass [localData] to close it. The two stores then diverge exactly as a real
/// device's do: a local-first write lands only in [localData] and is invisible
/// to every other client until [syncToRemote] runs, and a local-first read
/// cannot see what a peer wrote remotely. A wrong route then fails on its
/// **results**, which is what makes the assertion about behaviour rather than
/// about a recorded call.
///
/// It is opt-in because the nine callers that predate it assert routing
/// directly and would otherwise have to model sync to keep passing — they
/// specify the default, so the default did not move.
///
/// [remoteMetadata] is opt-in because most callers only care about values.
/// Supply one — shared by every client in the test, exactly as [remoteData] is
/// — when the behaviour under test writes or reads `Metadata`; without it a
/// `get` returns an [AtValue] with none, and an assertion about metadata would
/// fail for want of a fixture rather than for want of the feature.
///
/// Callers must `registerFallbackValue(AtKey())` in `setUpAll`.
MockAtClient buildRemoteBackedMockClient({
  required String atSign,
  required String enrollmentId,
  required Map<String, String> remoteData,
  Map<String, Metadata>? remoteMetadata,
  Map<String, String>? localData,
  Map<String, Metadata>? localMetadata,
}) {
  final atClient = MockAtClient();
  when(() => atClient.atChops).thenReturn(AtChopsImpl(
      AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair())));
  when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
  when(() => atClient.enrollmentId).thenReturn(enrollmentId);

  final remoteSecondary = MockRemoteSecondary();
  final atLookUp = MockAtLookupImpl();
  when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
  when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
  when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);

  // With no [localData] the two are the same map, which is the historical
  // behaviour: every write is visible to every client immediately.
  final localValues = localData ?? remoteData;
  final localMeta = localData == null ? remoteMetadata : localMetadata;

  when(() => atClient.put(any(), any(),
      putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((inv) {
    final atKey = inv.positionalArguments[0] as AtKey;
    final options =
        inv.namedArguments[#putRequestOptions] as PutRequestOptions?;
    final remote = options?.useRemoteAtServer ?? false;
    final values = remote ? remoteData : localValues;
    final meta = remote ? remoteMetadata : localMeta;
    values[atKey.toString()] = inv.positionalArguments[1];
    meta?[atKey.toString()] = atKey.metadata;
    return Future.value(true);
  });

  Future<AtValue> getFrom(Invocation inv) {
    final keyString = inv.positionalArguments[0].toString();
    final options =
        inv.namedArguments[#getRequestOptions] as GetRequestOptions?;
    final remote = options?.useRemoteAtServer ?? false;
    final values = remote ? remoteData : localValues;
    final meta = remote ? remoteMetadata : localMeta;
    final value = values[keyString];
    if (value == null) {
      // A local-first read of a key only the atServer holds is a miss, not a
      // fall-through to the remote. Treating it as a hit is precisely the
      // defect this fixture exists to be able to catch.
      throw AtKeyNotFoundException('$keyString not found');
    }
    return Future.value(AtValue()
      ..value = value
      ..metadata = meta?[keyString]);
  }

  when(() => atClient.get(any(),
      getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer(getFrom);
  when(() => atClient.get(any())).thenAnswer(getFrom);
  return atClient;
}

/// Copies everything a local-first write left in [localData] up to
/// [remoteData], the way sync eventually would.
///
/// Deliberately one-way and whole-store: modelling per-key commit ids would
/// make the fixture a sync implementation, and every defect this exists to
/// catch is about *whether* a value has reached the atServer, never about the
/// order in which several did.
void syncToRemote({
  required Map<String, String> localData,
  required Map<String, String> remoteData,
  Map<String, Metadata>? localMetadata,
  Map<String, Metadata>? remoteMetadata,
}) {
  remoteData.addAll(localData);
  if (localMetadata != null && remoteMetadata != null) {
    remoteMetadata.addAll(localMetadata);
  }
}
