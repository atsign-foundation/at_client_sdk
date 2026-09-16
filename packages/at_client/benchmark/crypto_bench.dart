// Run: dart run benchmark/crypto_bench.dart [--iterations N] [--json]
//
// Re-run on every key-shape change.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';

/// Measured cost of one operation, in microseconds.
class Timing {
  final String name;
  final String basis;
  final List<int> samples;

  Timing(this.name, this.basis, this.samples);

  int get median => _percentile(50);
  int get p90 => _percentile(90);

  int _percentile(int p) {
    final sorted = [...samples]..sort();
    return sorted[min(sorted.length - 1, (sorted.length * p) ~/ 100)];
  }

  /// This timing as a JSON-encodable map, with durations in microseconds.
  Map<String, Object?> toJson() => {
        'name': name,
        'basis': basis,
        'medianUs': median,
        'p90Us': p90,
        'samples': samples.length,
      };
}

/// Runs [body] [iterations] times after [warmup] untimed rounds, timing each
/// iteration separately.
///
/// [warmup] is generous on purpose: too few rounds leave JIT cost in the
/// samples.
Future<Timing> measure(
  String name,
  String basis,
  Future<void> Function() body, {
  required int iterations,
  int warmup = 25,
}) async {
  for (var i = 0; i < warmup; i++) {
    await body();
  }
  final samples = <int>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    await body();
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }
  return Timing(name, basis, samples);
}

/// The cost of the harness itself — an empty timed body.
Future<Timing> measureOverhead(int iterations) => measure(
      'harness loop (empty body)',
      'per iteration',
      () async {},
      iterations: iterations,
    );

/// Exercises every primitive once before anything is timed.
///
/// Per-measurement warmup is not enough on its own: it warms only its own
/// body, so whichever group runs first absorbs process-level JIT cost.
Future<void> prewarm() async {
  final data = payload(4096);
  final gcm = AesGcm256EncryptionAlgo(aesKey());
  final ctr = AESEncryptionAlgo(aesKey());
  final gcmIv = InitialisationVector(payload(12));
  final iv = InitialisationVector(payload(16));
  for (var i = 0; i < 25; i++) {
    await gcm.decrypt(await gcm.encrypt(data, iv: gcmIv), iv: gcmIv);
    await ctr.decrypt(await ctr.encrypt(data, iv: iv), iv: iv);
  }

  final xwing = XWingPureDartAlgo.instance;
  final pair = await xwing.generateKeyPair();
  final ck = payload(32);
  for (var i = 0; i < 3; i++) {
    await pqOpen(xwing, pair.secretKey,
        await pqSeal(xwing, pair.publicKey, ck, info: conveyanceInfo),
        info: conveyanceInfo);
  }

  final mldsa = MlDsa65PureDartAlgo();
  final keys = await mldsa.generateKeyPair();
  final challenge = payload(64);
  for (var i = 0; i < 3; i++) {
    final sig = await mldsa.signBytes(challenge, secretKey: keys.secretKey);
    await mldsa.verifyBytes(challenge,
        signature: sig, publicKey: keys.publicKey);
  }

  final rsa = RsaKeyPair.generate();
  final rsaSign = RsaSignatureAlgo.rsa2048();
  final rsaSecret = base64Decode(rsa.atPrivateKey.privateKey);
  final rsaPublic = base64Decode(rsa.atPublicKey.publicKey);
  final rsaEnc = RsaEncryptionAlgo.fromKeyPair(rsa);
  for (var i = 0; i < 3; i++) {
    await rsaSign.verifyBytes(challenge,
        signature: rsaSign.signBytesSync(challenge, secretKey: rsaSecret),
        publicKey: rsaPublic);
    rsaEnc.decrypt(rsaEnc.encrypt(ck));
  }
}

/// A payload of [bytes] bytes, identical on every call so no run measures a
/// different input.
Uint8List payload(int bytes) =>
    Uint8List.fromList(List<int>.generate(bytes, (i) => i % 256));

/// An AES-256 key, identical on every call so key material is never a variable.
AESKey aesKey() => AESKey(base64Encode(payload(32)));

/// The key-schedule binding a CK conveyance is sealed under.
///
/// Mirrors the `<providerId>:<owner>:<namespace>` shape a real conveyance uses:
/// `info` is an HKDF input, so an empty binding would measure a shorter key
/// schedule than anything in production pays for.
final Uint8List conveyanceInfo =
    Uint8List.fromList(utf8.encode('nskey:@benchmark:bench'));

/// Times the symmetric work every put and get pays once a content key exists.
Future<List<Timing>> perRecord(int iterations) async {
  final results = <Timing>[];
  final gcm = AesGcm256EncryptionAlgo(aesKey());
  final ctr = AESEncryptionAlgo(aesKey());
  final iv = InitialisationVector(payload(16));
  final gcmIv = InitialisationVector(payload(12));

  for (final size in [256, 4096, 65536]) {
    final data = payload(size);
    final sealed = await gcm.encrypt(data, iv: gcmIv);
    final legacySealed = await ctr.encrypt(data, iv: iv);

    results.add(await measure('nskey  AES-256-GCM encrypt ${size}B',
        'per record', () async => gcm.encrypt(data, iv: gcmIv),
        iterations: iterations));
    results.add(await measure('legacy AES-256-CTR encrypt ${size}B',
        'per record', () async => ctr.encrypt(data, iv: iv),
        iterations: iterations));
    results.add(await measure('nskey  AES-256-GCM decrypt ${size}B',
        'per record', () async => gcm.decrypt(sealed, iv: gcmIv),
        iterations: iterations));
    results.add(await measure('legacy AES-256-CTR decrypt ${size}B',
        'per record', () async => ctr.decrypt(legacySealed, iv: iv),
        iterations: iterations));
  }
  return results;
}

/// Times conveying a content key, which is paid once per (owner, namespace)
/// rather than per record.
Future<List<Timing>> perConveyance(int iterations) async {
  final results = <Timing>[];
  final xwing = XWingPureDartAlgo.instance;
  final pair = await xwing.generateKeyPair();
  final ck = payload(32);
  final envelope =
      await pqSeal(xwing, pair.publicKey, ck, info: conveyanceInfo);

  results.add(await measure(
      'nskey  X-Wing pqSeal (CK conveyance)',
      'per (owner, namespace)',
      () async => pqSeal(xwing, pair.publicKey, ck, info: conveyanceInfo),
      iterations: iterations));
  results.add(await measure(
      'nskey  X-Wing pqOpen (CK conveyance)',
      'per (owner, namespace)',
      () async => pqOpen(xwing, pair.secretKey, envelope, info: conveyanceInfo),
      iterations: iterations));
  results.add(await measure('nskey  X-Wing keygen', 'per key generation',
      () async => xwing.generateKeyPair(),
      iterations: iterations));

  final rsa = RsaKeyPair.generate();
  final rsaAlgo = RsaEncryptionAlgo.fromKeyPair(rsa);
  final wrapped = rsaAlgo.encrypt(ck);
  results.add(await measure('legacy RSA-2048 wrap (shared key)',
      'per (owner, recipient)', () async => rsaAlgo.encrypt(ck),
      iterations: iterations));
  results.add(await measure('legacy RSA-2048 unwrap (shared key)',
      'per (owner, recipient)', () async => rsaAlgo.decrypt(wrapped),
      iterations: iterations));
  return results;
}

/// Times signing and verifying one PKAM challenge, the whole of what an
/// authentication costs.
Future<List<Timing>> perAuth(int iterations) async {
  final results = <Timing>[];
  final challenge = payload(64);

  final mldsa = MlDsa65PureDartAlgo();
  final keys = await mldsa.generateKeyPair();
  final mlSig = await mldsa.signBytes(challenge, secretKey: keys.secretKey);

  results.add(await measure(
      'pq     ML-DSA-65 sign (PKAM challenge)',
      'per authentication',
      () async => mldsa.signBytes(challenge, secretKey: keys.secretKey),
      iterations: iterations));
  results.add(await measure(
      'pq     ML-DSA-65 verify (PKAM challenge)',
      'per authentication',
      () async => mldsa.verifyBytes(challenge,
          signature: mlSig, publicKey: keys.publicKey),
      iterations: iterations));

  final rsa = RsaKeyPair.generate();
  final rsaAlgo = RsaSignatureAlgo.rsa2048();
  // Decoded once, outside the measured closures: the base64 step is not part
  // of what these figures are about.
  final rsaSecret = base64Decode(rsa.atPrivateKey.privateKey);
  final rsaPublic = base64Decode(rsa.atPublicKey.publicKey);
  final rsaSig = rsaAlgo.signBytesSync(challenge, secretKey: rsaSecret);
  results.add(await measure(
      'legacy RSA-2048 sign (PKAM challenge)',
      'per authentication',
      () async => rsaAlgo.signBytesSync(challenge, secretKey: rsaSecret),
      iterations: iterations));
  results.add(await measure(
      'legacy RSA-2048 verify (PKAM challenge)',
      'per authentication',
      () async => rsaAlgo.verifyBytes(challenge,
          signature: rsaSig, publicKey: rsaPublic),
      iterations: iterations));
  return results;
}

/// Prints [timings] as a table under [heading], with [basisNote] naming the
/// denominator the figures are quoted against.
void report(String heading, String basisNote, List<Timing> timings) {
  stdout.writeln('');
  stdout.writeln(heading);
  stdout.writeln('  $basisNote');
  stdout.writeln('');
  final width =
      timings.map((t) => t.name.length).fold<int>(0, (a, b) => max(a, b));
  for (final t in timings) {
    stdout.writeln('  ${t.name.padRight(width)}  '
        '${_us(t.median).padLeft(10)}  (p90 ${_us(t.p90)})');
  }
}

String _us(int micros) =>
    micros >= 1000 ? '${(micros / 1000).toStringAsFixed(2)} ms' : '$micros us';

/// Runs every group and prints a table, or a JSON document when given `--json`.
Future<void> main(List<String> args) async {
  final iterations = args.contains('--iterations')
      ? int.parse(args[args.indexOf('--iterations') + 1])
      : 50;
  final asJson = args.contains('--json');

  await prewarm();
  final overhead = await measureOverhead(iterations);
  final record = await perRecord(iterations);
  final conveyance = await perConveyance(iterations);
  final auth = await perAuth(iterations);

  if (asJson) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'dartVersion': Platform.version,
      'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'processors': Platform.numberOfProcessors,
      'iterations': iterations,
      'harnessOverhead': overhead.toJson(),
      'perRecord': record.map((t) => t.toJson()).toList(),
      'perConveyance': conveyance.map((t) => t.toJson()).toList(),
      'perAuthentication': auth.map((t) => t.toJson()).toList(),
    }));
    return;
  }

  stdout.writeln('at_client PQ crypto bench');
  stdout.writeln('  ${Platform.version}');
  stdout.writeln('  ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion}, '
      '${Platform.numberOfProcessors} processors');
  stdout.writeln('  $iterations iterations, median reported');
  stdout.writeln('  harness loop overhead: ${_us(overhead.median)} '
      '— subtract nothing below this that is not well clear of it');

  report('PER RECORD — what every put/get pays once a content key exists',
      'Compare within this group only. This is the steady-state cost.', record);
  report(
      'PER CONVEYANCE — what PQ costs, paid ONCE per (owner, namespace)',
      'Do NOT add these to the per-record figures: a content key is conveyed '
          'once and\n  then covers every record in its scope, so charging this '
          'per put overstates it\n  by the number of records in the scope.',
      conveyance);
  report('PER AUTHENTICATION — the PKAM signature swap',
      'Paid once per connection, not per operation.', auth);

  stdout.writeln('');
  stdout.writeln('Three bases, never mixed. A single "PQ is N% slower" number '
      'over all of them\nwould be arithmetic on incomparable denominators.');
}
