import 'dart:typed_data';

import 'package:at_telemetry/at_telemetry.dart';

final class CallbackSigner implements AtTelemetrySigner {
  final Future<Uint8List> Function(List<int> message) _sign;

  @override
  final String algorithm;

  CallbackSigner(this._sign, {this.algorithm = 'ed25519'});

  @override
  Future<Uint8List> sign(List<int> message) => _sign(message);
}
