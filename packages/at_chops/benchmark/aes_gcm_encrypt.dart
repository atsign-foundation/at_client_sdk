/// Times AES-256-GCM encrypt per 1.1 MB chunk, for the OpenSSL FFI and the
/// pure-Dart implementation. Run by hand, AOT-compiled as an app ships it:
///
/// ```
/// dart compile exe benchmark/aes_gcm_encrypt.dart -o /tmp/aes_gcm_encrypt
/// /tmp/aes_gcm_encrypt [samples]
/// ```
///
/// Samples alternate between the implementations, and which goes first
/// alternates too. Every timed sample's output, from either implementation,
/// must have the same SHA-256 as the run's first timed output, and the first
/// that differs stops the run with a [StateError]; warmup calls are not
/// checked. Each implementation's line prints the median, minimum and maximum
/// time per call and that SHA-256, so two builds can be compared for both time
/// and bytes.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:crypto/crypto.dart' show sha256;

/// Plaintext bytes per encrypt call; with the tag, the output is 17 x 64 KiB.
const int chunkLength = 1114096;

/// Untimed calls per implementation before the first sample.
const int warmupCalls = 5;

Future<void> main(List<String> args) async {
  final int samples = args.isEmpty ? 50 : int.parse(args.first);
  final StringBuffer libPath = StringBuffer();
  final DynamicLibrary? lib = tryLoadLibCrypto(loadedPath: libPath);
  if (lib == null) {
    stderr.writeln('No usable libcrypto on this host; nothing to measure.');
    exit(1);
  }

  final Uint8List plain = Uint8List.fromList(
      List<int>.generate(chunkLength, (int i) => (i * 31 + 7) & 0xff));
  // NOTE: a fixed key and nonce, so every sample encrypts the same bytes.
  // Never reuse a (key, nonce) pair for real data.
  final AESKey key = AESKey(base64Encode(List<int>.generate(32, (int i) => i)));
  final InitialisationVector iv = InitialisationVector(Uint8List(12));

  final algos = <String, SymmetricEncryptionAlgorithm<Uint8List, Uint8List>>{
    'ffi': AesGcm256FfiAlgo.fromLib(lib, key),
    'pure': AesGcm256EncryptionAlgo(key),
  };
  final List<String> names = algos.keys.toList();
  final Map<String, List<int>> micros = {for (final n in names) n: <int>[]};
  String? reference;

  for (final String name in names) {
    for (int i = 0; i < warmupCalls; i++) {
      await algos[name]!.encrypt(plain, iv: iv);
    }
  }

  final Stopwatch sw = Stopwatch();
  for (int i = 0; i < samples; i++) {
    for (final String name in i.isEven ? names : names.reversed) {
      sw
        ..reset()
        ..start();
      final Uint8List out = await algos[name]!.encrypt(plain, iv: iv);
      sw.stop();
      micros[name]!.add(sw.elapsedMicroseconds);
      final String digest = sha256.convert(out).toString();
      reference ??= digest;
      if (digest != reference) {
        throw StateError('impl=$name sample $i output SHA-256 $digest differs '
            "from the run's first output's $reference");
      }
    }
  }

  stdout
    ..writeln('aes_gcm_encrypt dart=${Platform.version}')
    ..writeln('aes_gcm_encrypt libcrypto=$libPath');
  for (final String name in names) {
    final List<int> sorted = List<int>.of(micros[name]!)..sort();
    stdout.writeln('aes_gcm_encrypt impl=$name bytes=$chunkLength '
        'n=${sorted.length} median_us=${_median(sorted)} '
        'min_us=${sorted.first} max_us=${sorted.last} '
        'output_sha256=$reference');
  }
}

num _median(List<int> sorted) {
  final int mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}
