import 'dart:typed_data';

import 'package:at_telemetry/at_telemetry.dart';

final class CallbackSigner implements AtTelemetrySigner {
  final Future<Uint8List> Function(List<int> message) _sign;

  CallbackSigner(this._sign);

  @override
  Future<Uint8List> sign(List<int> message) => _sign(message);
}
