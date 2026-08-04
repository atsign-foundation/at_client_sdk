// Run: dart run benchmark/crypto_bench.dart [--iterations N] [--json]
//
// The durable artefact behind acceptance.md's "performance is measured, not
// assumed". Re-run it on every key-shape change; it is the instrument that
// pins the budget, not a one-off number.

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

  Map<String, Object?> toJson() => {
        'name': name,
        'basis': basis,
        'medianUs': median,
        'p90Us': p90,
        'samples': samples.length,
      };
}

/// Runs [body] [iterations] times after [warmup] untimed rounds.
///
/// Each iteration is timed separately and the median reported, because a total
/// divided by a count hides the distribution — and the pure-Dart PQ primitives
/// have a wide one.
///
/// [warmup] is deliberately generous. At 5 rounds the first measurement in the
/// process carried JIT cost into its samples, and the symptom was a legacy
/// encrypt that came out *slower* at 256B than at 4096B — an impossible
/// ordering, and the instrument saying so.
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
///
/// Reported rather than subtracted. A measurement whose background is not
/// stated cannot be checked, and if this is ever a large share of a headline
/// number then that number is measuring the instrument.
Future<Timing> measureOverhead(int iterations) => measure(
      'harness loop (empty body)',
      'per iteration',
      () async {},
      iterations: iterations,
    );

/// Exercises every primitive once before anything is timed.
///
/// Per-measurement warmup is not enough on its own: it warms only its own
/// body, so whichever group runs first still absorbs process-level JIT cost.
/// The symptom was a legacy encrypt reading slower at 256B than at 4096B, and
/// the elevated figure moving to whichever size was measured first — an
/// ordering that cannot be a property of the code.
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
    await pqOpen(xwing, pair.secretKey, await pqSeal(xwing, pair.publicKey, ck));
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
  final rsaSign = RsaSigningAlgo(rsa, HashingAlgoType.sha256);
  final rsaEnc = RsaEncryptionAlgo.fromKeyPair(rsa);
  for (var i = 0; i < 3; i++) {
    rsaSign.verify(challenge, rsaSign.sign(challenge),
        publicKey: rsa.atPublicKey.publicKey);
    rsaEnc.decrypt(rsaEnc.encrypt(ck));
  }
}

Uint8List payload(int bytes) =>
    Uint8List.fromList(List<int>.generate(bytes, (i) => i % 256));

AESKey aesKey() => AESKey(base64Encode(payload(32)));

Future<List<Timing>> perRecord(int iterations) async {
  final results = <Timing>[];
  // A content key is already established at this point — these are the costs
  // every put and get actually pays in steady state.
  final gcm = AesGcm256EncryptionAlgo(aesKey());
  final ctr = AESEncryptionAlgo(aesKey());
  final iv = InitialisationVector(payload(16));
  final gcmIv = InitialisationVector(payload(12));

  for (final size in [256, 4096, 65536]) {
    final data = payload(size);
    final sealed = await gcm.encrypt(data, iv: gcmIv);
    final legacySealed = await ctr.encrypt(data, iv: iv);

    results.add(await measure(
        'nskey  AES-256-GCM encrypt ${size}B', 'per record',
        () async => gcm.encrypt(data, iv: gcmIv),
        iterations: iterations));
    results.add(await measure(
        'legacy AES-256-CTR encrypt ${size}B', 'per record',
        () async => ctr.encrypt(data, iv: iv),
        iterations: iterations));
    results.add(await measure(
        'nskey  AES-256-GCM decrypt ${size}B', 'per record',
        () async => gcm.decrypt(sealed, iv: gcmIv),
        iterations: iterations));
    results.add(await measure(
        'legacy AES-256-CTR decrypt ${size}B', 'per record',
        () async => ctr.decrypt(legacySealed, iv: iv),
        iterations: iterations));
  }
  return results;
}

Future<List<Timing>> perConveyance(int iterations) async {
  final results = <Timing>[];
  // This is where PQ actually costs something, and it is paid ONCE per
  // (owner, namespace) — not per record. Charging it per put, which a naive
  // end-to-end latency delta does, overstates it by the number of records in
  // the scope.
  final xwing = XWingPureDartAlgo.instance;
  final pair = await xwing.generateKeyPair();
  final ck = payload(32); // a content key is what actually gets conveyed
  final envelope = await pqSeal(xwing, pair.publicKey, ck);

  results.add(await measure('nskey  X-Wing pqSeal (CK conveyance)',
      'per (owner, namespace)', () async => pqSeal(xwing, pair.publicKey, ck),
      iterations: iterations));
  results.add(await measure('nskey  X-Wing pqOpen (CK conveyance)',
      'per (owner, namespace)',
      () async => pqOpen(xwing, pair.secretKey, envelope),
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

Future<List<Timing>> perAuth(int iterations) async {
  final results = <Timing>[];
  // The PKAM signature swap. Auth needs a signature only — the per-connection
  // challenge gives freshness and TLS gives the channel — so this is the whole
  // of what PQ costs an authentication.
  final challenge = payload(64);

  final mldsa = MlDsa65PureDartAlgo();
  final keys = await mldsa.generateKeyPair();
  final mlSig = await mldsa.signBytes(challenge, secretKey: keys.secretKey);

  results.add(await measure('pq     ML-DSA-65 sign (PKAM challenge)',
      'per authentication',
      () async => mldsa.signBytes(challenge, secretKey: keys.secretKey),
      iterations: iterations));
  results.add(await measure('pq     ML-DSA-65 verify (PKAM challenge)',
      'per authentication',
      () async => mldsa.verifyBytes(challenge,
          signature: mlSig, publicKey: keys.publicKey),
      iterations: iterations));

  final rsa = RsaKeyPair.generate();
  final rsaAlgo = RsaSigningAlgo(rsa, HashingAlgoType.sha256);
  final rsaSig = rsaAlgo.sign(challenge);
  results.add(await measure('legacy RSA-2048 sign (PKAM challenge)',
      'per authentication', () async => rsaAlgo.sign(challenge),
      iterations: iterations));
  results.add(await measure('legacy RSA-2048 verify (PKAM challenge)',
      'per authentication',
      () async => rsaAlgo.verify(challenge, rsaSig,
          publicKey: rsa.atPublicKey.publicKey),
      iterations: iterations));
  return results;
}

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

String _us(int micros) => micros >= 1000
    ? '${(micros / 1000).toStringAsFixed(2)} ms'
    : '$micros us';

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

  report(
      'PER RECORD — what every put/get pays once a content key exists',
      'Compare within this group only. This is the steady-state cost.',
      record);
  report(
      'PER CONVEYANCE — what PQ costs, paid ONCE per (owner, namespace)',
      'Do NOT add these to the per-record figures: a content key is conveyed '
          'once and\n  then covers every record in its scope, so charging this '
          'per put overstates it\n  by the number of records in the scope.',
      conveyance);
  report(
      'PER AUTHENTICATION — the PKAM signature swap',
      'Paid once per connection, not per operation.',
      auth);

  stdout.writeln('');
  stdout.writeln('Three bases, never mixed. A single "PQ is N% slower" number '
      'over all of them\nwould be arithmetic on incomparable denominators.');
}
