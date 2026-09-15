/// Checks that [AesCtrFfiCipher.dispose] actually releases its native context.
///
/// A leaked `EVP_CIPHER_CTX` per stream is the predicted defect of the
/// incremental cipher, and it is invisible in a passing test suite: the leak is
/// native memory, so nothing in Dart notices. This is deliberately **not** a
/// test — RSS is too noisy for a threshold that would be either flaky or
/// meaningless. Run it by hand and read the two numbers:
///
/// ```
/// dart run benchmark/aes_ctr_ctx_leak.dart              # disposes
/// dart run benchmark/aes_ctr_ctx_leak.dart --no-dispose # control, must grow
/// ```
///
/// The control exists to prove the measurement has resolution at all. If both
/// runs look the same, the probe is not sensitive enough to conclude anything
/// — it does not mean there is no leak.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';

const int iterations = 10000;

void main(List<String> args) {
  final bool dispose = !args.contains('--no-dispose');
  final StringBuffer libPath = StringBuffer();
  final DynamicLibrary? lib = tryLoadLibCrypto(loadedPath: libPath);
  if (lib == null) {
    stderr.writeln('No usable libcrypto on this host; nothing to measure.');
    exit(0);
  }

  final AESKey key = AESKey(
      base64Encode(List<int>.generate(32, (int i) => i * 7 & 0xff)));
  final InitialisationVector iv = InitialisationVector(
      Uint8List.fromList(List<int>.generate(16, (int i) => i * 11 & 0xff)));
  final Uint8List chunk = Uint8List(4096);

  // Settle allocator behaviour before the baseline is taken.
  for (int i = 0; i < 100; i++) {
    AesCtrFfiCipher.fromLib(lib, key, iv)
      ..update(chunk)
      ..dispose();
  }

  final int before = ProcessInfo.currentRss;
  final List<AesCtrFfiCipher> held = <AesCtrFfiCipher>[];
  for (int i = 0; i < iterations; i++) {
    final AesCtrFfiCipher cipher = AesCtrFfiCipher.fromLib(lib, key, iv);
    cipher.update(chunk);
    if (dispose) {
      cipher.dispose();
    } else {
      // Held so the Finalizer backstop cannot fire and mask the control.
      held.add(cipher);
    }
  }
  final int after = ProcessInfo.currentRss;

  stdout
    ..writeln('mode:      ${dispose ? 'dispose' : 'NO dispose (control)'}')
    ..writeln('libcrypto: $libPath')
    ..writeln('iterations: $iterations')
    ..writeln('RSS before: ${_mib(before)}')
    ..writeln('RSS after:  ${_mib(after)}')
    ..writeln('delta:      ${_mib(after - before)} '
        '(${((after - before) / iterations).toStringAsFixed(1)} bytes/cipher)')
    ..writeln('held:       ${held.length}');
}

String _mib(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
