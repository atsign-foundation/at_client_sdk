import 'dart:typed_data';

abstract interface class AtTelemetrySigner {
  Future<Uint8List> sign(List<int> message);
}
