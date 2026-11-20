import 'dart:math';
import 'dart:typed_data';

/// [length] bytes from the platform random source.
Uint8List randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}
