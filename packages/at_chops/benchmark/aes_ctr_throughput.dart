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
/// - **DartAesCtr (stream)** — `encryptStream`, throttle and all:
///   `Cipher.encryptStream` sleeps 1 ms every 4 MB to yield the event loop,
///   and stripping it would flatter the FFI number. This arm is
///   `package:cryptography`, not the `better_cryptography` fork behind
///   [AESEncryptionAlgo] — it models the streaming consumer being replaced,
///   not at_chops's own one-shot fallback.
/// - **DartAesCtr (raw)** — the same primitive driven chunk by chunk with no
///   stream machinery, so the primitive-vs-primitive comparison stays visible.
///
/// Every cell is sampled [repetitions] times, interleaved across sizes and
/// contenders rather than measured one size at a time. Repeated runs of a
/// contiguous size-at-a-time pass disagree by several times on the same cell,
/// and by more than the chunk-size difference the table exists to show, so
/// such a pass reports position-in-run as though it were chunk size. The cause
/// of that drift is not established here, so the table prints the median and
/// the observed spread instead of assuming it away: **a row whose spread is
/// comparable to the gap between rows says nothing about chunk size.**
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Bytes pushed through each contender in one timed sample.
const int totalBytes = 64 * 1024 * 1024;

/// A warmup pass at a fraction of [totalBytes] — enough to reach steady state
/// and to fault in the cipher's scratch buffers, without paying for a second
/// full run of everything.
const int warmupBytes = 16 * 1024 * 1024;

/// Timed samples per cell. Three is the fewest that gives a median.
const int repetitions = 3;

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

  final int warmupChunk = chunkSizes.reduce(max);
  _ffiPass(warmupBytes, warmupChunk, lib, keyBytes, ivBytes);
  await _dartStreamPass(warmupBytes, warmupChunk, keyBytes, ivBytes);
  await _dartRawPass(warmupBytes, warmupChunk, keyBytes, ivBytes);

  final Map<int, List<double>> ffi = _emptySamples();
  final Map<int, List<double>> dartStream = _emptySamples();
  final Map<int, List<double>> dartRaw = _emptySamples();

  for (int rep = 1; rep <= repetitions; rep++) {
    for (final int size in chunkSizes) {
      stderr.write('\rsample $rep/$repetitions at ${size ~/ 1024} KB     ');
      ffi[size]!.add(_ffiPass(totalBytes, size, lib, keyBytes, ivBytes));
      dartStream[size]!
          .add(await _dartStreamPass(totalBytes, size, keyBytes, ivBytes));
      dartRaw[size]!
          .add(await _dartRawPass(totalBytes, size, keyBytes, ivBytes));
    }
  }
  stderr.writeln('\r                              ');

  stdout
    ..writeln('Host:      ${Platform.operatingSystemVersion}')
    ..writeln('Dart:      ${Platform.version}')
    ..writeln('libcrypto: $libPath')
    ..writeln('Ceiling:   ${_opensslCeiling()}')
    ..writeln('Sample:    ${totalBytes ~/ (1024 * 1024)} MB '
        '× $repetitions, interleaved; median (spread)')
    ..writeln()
    ..writeln(
        '| Chunk | at_chops FFI | DartAesCtr (stream) | DartAesCtr (raw) |')
    ..writeln('|---|---|---|---|');

  for (final int size in chunkSizes) {
    stdout.writeln('| ${size ~/ 1024} KB '
        '| ${_cell(ffi[size]!)} '
        '| ${_cell(dartStream[size]!)} '
        '| ${_cell(dartRaw[size]!)} |');
  }

  stdout
    ..writeln()
    ..writeln(_verdict(_medians(ffi), _medians(dartStream)));
}

Map<int, List<double>> _emptySamples() =>
    <int, List<double>>{for (final int s in chunkSizes) s: <double>[]};

Map<int, double> _medians(Map<int, List<double>> samples) => samples
    .map((int size, List<double> s) => MapEntry<int, double>(size, _median(s)));

/// The reported figure. A mean would let one slow sample move the row.
double _median(List<double> samples) {
  final List<double> sorted = List<double>.of(samples)..sort();
  final int mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Median plus half-range, so a reader can tell a resolved row from noise.
String _cell(List<double> samples) {
  final double lo = samples.reduce(min);
  final double hi = samples.reduce(max);
  final double half = 100 * (hi - lo) / (hi + lo);
  return '${_median(samples).toStringAsFixed(0)} MB/s '
      '(±${half.toStringAsFixed(0)}%)';
}

/// The line the stream adapter's design depends on: below a crossover, the
/// adapter has to coalesce chunks or route them to pure-Dart.
String _verdict(Map<int, double> ffi, Map<int, double> dartStream) {
  final List<int> sizes = List<int>.of(chunkSizes)..sort();
  final List<int> losses =
      sizes.where((int size) => ffi[size]! <= dartStream[size]!).toList();
  if (losses.isEmpty) {
    final double worst =
        sizes.map((int size) => ffi[size]! / dartStream[size]!).reduce(min);
    return 'VERDICT: no crossover — FFI wins at every size tested, by '
        '${worst.toStringAsFixed(1)}x at worst. No coalescing needed.';
  }
  final int largestLoss = losses.last;
  final Iterable<int> wins = sizes.where((int s) => s > largestLoss);
  return 'VERDICT: FFI loses at or below ${largestLoss ~/ 1024} KB, and wins '
      '${wins.isEmpty ? 'at no size tested' : 'from ${wins.first ~/ 1024} KB up'}'
      '. The adapter must coalesce to ${largestLoss ~/ 1024} KB, or route '
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
