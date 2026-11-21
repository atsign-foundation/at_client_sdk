/// Times ChaCha20-Poly1305 encrypt at four plaintext lengths, from 32 bytes to
/// the 1.1 MB chunk the AES-256-GCM bench uses. Run by hand, AOT-compiled as
/// an app ships it:
///
/// ```
/// dart compile exe benchmark/chacha20_poly1305_encrypt.dart -o /tmp/chacha
/// /tmp/chacha [samples]
/// ```
///
/// A sample times a batch of calls at one size, enough calls for the batch to
/// cover about 64 KiB of plaintext, and the sizes take turns going first.
/// Every output of every timed call must have the same SHA-256 as the first
/// timed output at its size, and the first that differs stops the run with a
/// [StateError]; warmup calls are not checked. Each size's line prints the
/// median, minimum and maximum time per call in nanoseconds and that SHA-256,
/// so two builds can be compared for both time and bytes.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:crypto/crypto.dart' show sha256;

/// Plaintext lengths timed; the last is the AES-256-GCM bench's chunk.
const List<int> plaintextLengths = [32, 192, 5474, 1114096];

/// Plaintext bytes each timed batch covers, at least one call.
const int batchBytes = 65536;

/// Untimed batches per size before the first sample.
const int warmupBatches = 5;

Future<void> main(List<String> args) async {
  final int samples = args.isEmpty ? 50 : int.parse(args.first);
  const ChaCha20Poly1305Algo algo = ChaCha20Poly1305Algo();
  // NOTE: a fixed key and nonce, so every sample encrypts the same bytes.
  // Never reuse a (key, nonce) pair for real data.
  final Uint8List key = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final Uint8List nonce = Uint8List(12);
  final Map<int, Uint8List> plain = {
    for (final n in plaintextLengths)
      n: Uint8List.fromList(List<int>.generate(n, (i) => (i * 31 + 7) & 0xff)),
  };
  int callsFor(int n) => n >= batchBytes ? 1 : batchBytes ~/ n;
  final Map<int, List<double>> nanos = {
    for (final n in plaintextLengths) n: <double>[],
  };
  final Map<int, String> reference = {};

  for (final n in plaintextLengths) {
    for (int b = 0; b < warmupBatches; b++) {
      for (int c = 0; c < callsFor(n); c++) {
        await algo.encrypt(plain[n]!, key: key, nonce: nonce);
      }
    }
  }

  final Stopwatch sw = Stopwatch();
  for (int i = 0; i < samples; i++) {
    for (int s = 0; s < plaintextLengths.length; s++) {
      final int n = plaintextLengths[(i + s) % plaintextLengths.length];
      final int calls = callsFor(n);
      final List<Uint8List> outs = List<Uint8List>.filled(calls, Uint8List(0));
      sw
        ..reset()
        ..start();
      for (int c = 0; c < calls; c++) {
        outs[c] = await algo.encrypt(plain[n]!, key: key, nonce: nonce);
      }
      sw.stop();
      nanos[n]!.add(sw.elapsedMicroseconds * 1000 / calls);
      for (int c = 0; c < calls; c++) {
        final String digest = sha256.convert(outs[c]).toString();
        final String expected = reference[n] ??= digest;
        if (digest != expected) {
          throw StateError('bytes=$n sample $i call $c output SHA-256 '
              "$digest differs from the run's first output's $expected");
        }
      }
    }
  }

  stdout.writeln('chacha20_poly1305_encrypt dart=${Platform.version}');
  for (final n in plaintextLengths) {
    final List<double> sorted = List<double>.of(nanos[n]!)..sort();
    stdout.writeln('chacha20_poly1305_encrypt bytes=$n calls=${callsFor(n)} '
        'n=${sorted.length} median_ns=${_median(sorted).round()} '
        'min_ns=${sorted.first.round()} max_ns=${sorted.last.round()} '
        'output_sha256=${reference[n]}');
  }
}

double _median(List<double> sorted) {
  final int mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}
