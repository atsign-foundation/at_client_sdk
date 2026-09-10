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
/// Without [localData] one map backs both stores, so the fixture cannot tell a
/// local-first write from a remote-first one and a test that cares about
/// routing has to assert the routing directly rather than the result. Pass
/// [localData] and the two stores diverge as a real device's do: a local-first
/// write lands only in [localData] and is invisible to every other client
/// until [syncToRemote] runs, and a local-first read cannot see what a peer
/// wrote remotely, so a wrong route fails on its results.
///
/// Supply [remoteMetadata] — shared by every client in the test, exactly as
/// [remoteData] is — when the behaviour under test writes or reads `Metadata`;
/// without it a `get` returns an [AtValue] with none, and an assertion about
/// metadata fails for want of a fixture rather than for want of the feature.
///
/// Callers must `registerFallbackValue(AtKey())` in `setUpAll`; this registers
/// the [NotificationParams] fallback its own `notify` matcher needs.
MockAtClient buildRemoteBackedMockClient({
  required String atSign,
  required String enrollmentId,
  required Map<String, String> remoteData,
  Map<String, Metadata>? remoteMetadata,
  Map<String, String>? localData,
  Map<String, Metadata>? localMetadata,
  List<String>? keyEstablishmentAlgorithms,
  PqPosture? posture,
}) {
  registerFallbackValue(NotificationParams.forUpdate(AtKey()));
  final atClient = MockAtClient(
      keyEstablishmentAlgorithms: keyEstablishmentAlgorithms, posture: posture);
  when(() => atClient.atChops).thenReturn(AtChopsImpl(
      AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair())));
  when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
  when(() => atClient.enrollmentId).thenReturn(enrollmentId);

  final remoteSecondary = MockRemoteSecondary();
  final atLookUp = MockAtLookupImpl();
  when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
  when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
  when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);

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

  when(() => atClient.delete(any(),
          isDedicated: any(named: 'isDedicated'),
          deleteRequestOptions: any(named: 'deleteRequestOptions')))
      .thenAnswer((inv) {
    final keyString = inv.positionalArguments[0].toString();
    final options =
        inv.namedArguments[#deleteRequestOptions] as DeleteRequestOptions?;
    final remote = options?.useRemoteAtServer ?? false;
    (remote ? remoteData : localValues).remove(keyString);
    (remote ? remoteMetadata : localMeta)?.remove(keyString);
    return Future.value(true);
  });

  // NOTE: the notify succeeds and delivers nothing. It models the wake-up a
  // writer fires after storing a value another enrollment must read - a
  // best-effort nudge on top of a stored envelope, never the route the value
  // itself travels. A fixture that delivered would hand every test built on
  // this a second, asynchronous path to the envelope it drives by hand.
  final notifications = MockNotificationService();
  when(() => atClient.notificationService).thenReturn(notifications);
  when(() => notifications.notify(any(),
      waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
      checkForFinalDeliveryStatus: any(named: 'checkForFinalDeliveryStatus'),
      encryptValue: any(named: 'encryptValue'),
      onSuccess: any(named: 'onSuccess'),
      onError: any(named: 'onError'),
      onSentToSecondary:
          any(named: 'onSentToSecondary'))).thenAnswer(
      (_) async => NotificationResult());

  Future<AtValue> getFrom(Invocation inv) {
    final keyString = inv.positionalArguments[0].toString();
    final options =
        inv.namedArguments[#getRequestOptions] as GetRequestOptions?;
    final remote = options?.useRemoteAtServer ?? false;
    final values = remote ? remoteData : localValues;
    final meta = remote ? remoteMetadata : localMeta;
    final value = values[keyString];
    if (value == null) {
      // NOTE: a local-first read of a key only the atServer holds is a miss,
      // not a fall-through to the remote.
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
/// One-way and whole-store: what it models is whether a value has reached the
/// atServer, never the order in which several did.
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
