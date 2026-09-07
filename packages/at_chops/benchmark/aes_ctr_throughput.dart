/// Measures AES-CTR throughput at the chunk sizes a socket actually delivers.
///
/// FFI per-call cost is fixed; pure-Dart cost is per byte. Somewhere between
/// them is a crossover, and a streaming consumer that gets small chunks needs
/// to know where it is. Run by hand:
///
/// ```
/// dart run benchmark/aes_ctr_throughput.dart
/// ```
///
/// Three contenders per row:
///
/// - **at_chops FFI** — one long-lived [AesCtrFfiCipher], as a tunnel uses it.
/// - **DartAesCtr (stream)** — `encryptStream`, throttle and all. This is the
///   real replaced behaviour: `Cipher.encryptStream` sleeps 1 ms every 4 MB to
///   yield the event loop. Stripping it would flatter the FFI number.
/// - **DartAesCtr (raw)** — the same primitive driven chunk by chunk with no
///   stream machinery, so the primitive-vs-primitive comparison stays visible.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Bytes pushed through each contender in a timed pass.
const int totalBytes = 256 * 1024 * 1024;

/// A warmup pass at a fraction of [totalBytes] — enough to reach steady state
/// and to fault in the cipher's scratch buffers, without paying for a second
/// full run of everything.
const int warmupBytes = 16 * 1024 * 1024;

const List<int> chunkSizes = <int>[1024, 4096, 16384, 65536];

void main() async {
  final StringBuffer libPath = StringBuffer();
  final DynamicLibrary? lib = tryLoadLibCrypto(loadedPath: libPath);
  if (lib == null) {
    stderr.writeln('No usable libcrypto on this host; nothing to measure.');
    exit(0);
  }

  // One key and IV for every row, so the rows are comparable to each other.
  final Uint8List keyBytes =
      Uint8List.fromList(List<int>.generate(32, (int i) => i * 7 & 0xff));
  final Uint8List ivBytes =
      Uint8List.fromList(List<int>.generate(16, (int i) => i * 11 & 0xff));

  stdout
    ..writeln('Host:      ${Platform.operatingSystemVersion}')
    ..writeln('Dart:      ${Platform.version}')
    ..writeln('libcrypto: $libPath')
    ..writeln('Ceiling:   ${_opensslCeiling()}')
    ..writeln('Pass:      ${totalBytes ~/ (1024 * 1024)} MB')
    ..writeln()
    ..writeln(
        '| Chunk | at_chops FFI | DartAesCtr (stream) | DartAesCtr (raw) |')
    ..writeln('|---|---|---|---|');

  final Map<int, double> ffi = <int, double>{};
  final Map<int, double> dartStream = <int, double>{};

  for (final int size in chunkSizes) {
    _ffiPass(warmupBytes, size, lib, keyBytes, ivBytes);
    ffi[size] = _ffiPass(totalBytes, size, lib, keyBytes, ivBytes);

    await _dartStreamPass(warmupBytes, size, keyBytes, ivBytes);
    dartStream[size] =
        await _dartStreamPass(totalBytes, size, keyBytes, ivBytes);

    await _dartRawPass(warmupBytes, size, keyBytes, ivBytes);
    final double raw = await _dartRawPass(totalBytes, size, keyBytes, ivBytes);

    stdout.writeln('| ${size ~/ 1024} KB '
        '| ${ffi[size]!.toStringAsFixed(0)} MB/s '
        '| ${dartStream[size]!.toStringAsFixed(0)} MB/s '
        '| ${raw.toStringAsFixed(0)} MB/s |');
  }

  stdout
    ..writeln()
    ..writeln(_verdict(ffi, dartStream));
}

/// The line the stream adapter's design depends on: below a crossover, the
/// adapter has to coalesce chunks or route them to pure-Dart.
String _verdict(Map<int, double> ffi, Map<int, double> dartStream) {
  final List<int> losses = chunkSizes
      .where((int size) => ffi[size]! <= dartStream[size]!)
      .toList();
  if (losses.isEmpty) {
    final double worst = chunkSizes
        .map((int size) => ffi[size]! / dartStream[size]!)
        .reduce((double a, double b) => a < b ? a : b);
    return 'VERDICT: no crossover — FFI wins at every size tested, by '
        '${worst.toStringAsFixed(1)}x at worst. No coalescing needed.';
  }
  final int largestLoss = losses.last;
  final Iterable<int> wins = chunkSizes.where((int s) => s > largestLoss);
  return 'VERDICT: FFI loses at or below ${largestLoss ~/ 1024} KB, and wins '
      'from ${wins.isEmpty ? 'nowhere up to 64 KB' : '${wins.first ~/ 1024} KB'} '
      'up. The adapter must coalesce to ${largestLoss ~/ 1024} KB, or route '
      'smaller chunks to pure-Dart.';
}

/// `openssl speed` as the hardware ceiling — informational, not a contender.
String _opensslCeiling() {
  try {
    final ProcessResult result = Process.runSync(
        'openssl', <String>['speed', '-evp', 'aes-256-ctr', '-elapsed']);
    if (result.exitCode != 0) return 'n/a';
    final String line = result.stdout
        .toString()
        .split('\n')
        .lastWhere((String l) => l.toLowerCase().contains('aes-256-ctr'),
            orElse: () => '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return line.isEmpty ? 'n/a' : line;
  } on ProcessException {
    return 'n/a (openssl not on PATH)';
  }
}

/// One long-lived context for the whole pass, which is how a tunnel uses it.
double _ffiPass(
    int bytes, int chunkSize, DynamicLibrary lib, Uint8List key, Uint8List iv) {
  final AesCtrFfiCipher cipher = AesCtrFfiCipher.fromLib(
      lib, AESKey(base64Encode(key)), InitialisationVector(iv));
  // Allocated before the stopwatch: the buffer is the caller's, not the
  // cipher's, and a socket would have handed it over already.
  final Uint8List chunk = Uint8List(chunkSize);
  final int chunks = bytes ~/ chunkSize;

  final Stopwatch sw = Stopwatch()..start();
  for (int i = 0; i < chunks; i++) {
    cipher.update(chunk);
  }
  sw.stop();
  cipher.dispose();
  return _throughput(chunks * chunkSize, sw);
}

/// `encryptStream`, throttle included — the behaviour actually being replaced.
Future<double> _dartStreamPass(
    int bytes, int chunkSize, Uint8List key, Uint8List iv) async {
  final DartAesCtr cipher =
      DartAesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
  final Uint8List chunk = Uint8List(chunkSize);
  final int chunks = bytes ~/ chunkSize;

  Stream<List<int>> source() async* {
    for (int i = 0; i < chunks; i++) {
      yield chunk;
    }
  }

  final Stopwatch sw = Stopwatch()..start();
  await cipher
      .encryptStream(source(),
          secretKey: SecretKey(key), nonce: iv, onMac: (Mac mac) {})
      .drain<void>();
  sw.stop();
  return _throughput(chunks * chunkSize, sw);
}

/// The same primitive with no stream machinery around it.
Future<double> _dartRawPass(
    int bytes, int chunkSize, Uint8List key, Uint8List iv) async {
  final DartAesCtr cipher =
      DartAesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
  final Uint8List chunk = Uint8List(chunkSize);
  final int chunks = bytes ~/ chunkSize;

  final CipherState state = cipher.newState();
  await state.initialize(
      isEncrypting: true, secretKey: SecretKey(key), nonce: iv);

  final Stopwatch sw = Stopwatch()..start();
  for (int i = 0; i < chunks; i++) {
    state.convertChunkSync(chunk);
  }
  sw.stop();
  return _throughput(chunks * chunkSize, sw);
}

double _throughput(int bytes, Stopwatch sw) =>
    (bytes / (1024 * 1024)) / (sw.elapsedMicroseconds / 1000000);
