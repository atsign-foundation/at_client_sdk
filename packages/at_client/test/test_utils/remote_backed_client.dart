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
/// The fixture deliberately cannot tell a local-first write from a remote-first
/// one — one map backs both — so a test that cares about routing has to assert
/// the routing directly rather than the result.
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
}) {
  final atClient = MockAtClient();
  when(() => atClient.atChops).thenReturn(
      AtChopsImpl(AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair())));
  when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
  when(() => atClient.enrollmentId).thenReturn(enrollmentId);

  final remoteSecondary = MockRemoteSecondary();
  final atLookUp = MockAtLookUpImpl();
  when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
  when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
  when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);

  when(() => atClient.put(any(), any(),
      putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((inv) {
    final atKey = inv.positionalArguments[0] as AtKey;
    remoteData[atKey.toString()] = inv.positionalArguments[1];
    remoteMetadata?[atKey.toString()] = atKey.metadata;
    return Future.value(true);
  });

  Future<AtValue> getFromRemoteData(Invocation inv) {
    final keyString = inv.positionalArguments[0].toString();
    final value = remoteData[keyString];
    if (value == null) {
      throw AtKeyNotFoundException('$keyString not found');
    }
    return Future.value(AtValue()
      ..value = value
      ..metadata = remoteMetadata?[keyString]);
  }

  when(() => atClient.get(any(),
          getRequestOptions: any(named: 'getRequestOptions')))
      .thenAnswer(getFromRemoteData);
  when(() => atClient.get(any())).thenAnswer(getFromRemoteData);
  return atClient;
}
