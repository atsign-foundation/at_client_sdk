import 'dart:typed_data';

import 'package:at_auth/passkey.dart';

/// A scripted [PasskeyPort]: records calls, returns [resultPrfFirst], or
/// throws [failure] from either ceremony.
class FakePasskeyPort implements PasskeyPort {
  final calls = <String>[];
  Uint8List? lastGetAllowCredential;
  Uint8List? lastGetEvalInput;
  String? lastCreateAtSign;
  DateTime? lastCreateEnrolledAt;
  String? lastCreateDeviceName;
  Uint8List? resultPrfFirst;
  Uint8List resultCredentialId = Uint8List.fromList([1, 2, 3]);
  Object? failure;

  /// The create ceremony's PRF extension result: true, false, or null when
  /// the extension result is absent.
  bool? createPrfEnabled;

  @override
  Future<PasskeyCreation> create(
      {required String atSign,
      required DateTime enrolledAt,
      required String deviceName}) async {
    calls.add('create');
    lastCreateAtSign = atSign;
    lastCreateEnrolledAt = enrolledAt;
    lastCreateDeviceName = deviceName;
    if (failure != null) throw failure!;
    return (credentialId: resultCredentialId, prfEnabled: createPrfEnabled);
  }

  @override
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    calls.add('get');
    lastGetAllowCredential = allowCredential;
    lastGetEvalInput = evalInput;
    if (failure != null) throw failure!;
    return (credentialId: resultCredentialId, prfFirst: resultPrfFirst);
  }
}

/// A [PrfEnvironment] with a settable clock, capability answer and miss flag.
class FakePrfEnvironment implements PrfEnvironment {
  bool? capability;
  DateTime? missAt;
  var clock = DateTime.utc(2026, 11, 13);

  @override
  Future<bool?> clientCapabilityPrf() async => capability;

  @override
  DateTime? missRecordedAt() => missAt;

  @override
  void recordMiss(DateTime at) => missAt = at;

  @override
  void clearMiss() => missAt = null;

  @override
  DateTime now() => clock;
}

/// Wraps a [RecordSealer], counting calls and recording that it was closed.
class SpyRecordSealer implements RecordSealer {
  SpyRecordSealer(this.inner);
  final RecordSealer inner;
  var closeCalls = 0;
  var sealCalls = 0;
  final aads = <List<int>>[];

  @override
  Future<Uint8List> seal(Uint8List iv, List<int> plaintext, List<int> aad) {
    sealCalls++;
    aads.add(aad);
    return inner.seal(iv, plaintext, aad);
  }

  @override
  Future<Uint8List> open(Uint8List iv, Uint8List ciphertext, List<int> aad) =>
      inner.open(iv, ciphertext, aad);

  @override
  void close() {
    closeCalls++;
    inner.close();
  }
}
