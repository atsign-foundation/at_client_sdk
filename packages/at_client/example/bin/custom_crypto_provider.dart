import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

import 'package:at_client_examples/init_example_context.dart';

// ---------------------------------------------------------------------------
// Step 1: Implement CryptoProvider
//
// This toy provider XOR-encodes values with a fixed key just to show the
// shape of the interface. Replace with a real algorithm in production.
// ---------------------------------------------------------------------------
// Providers are stateless: everything they need arrives per call. The same
// instance is safely shared across atSigns.
class XorCryptoProvider implements CryptoProvider {
  static const _xorKey = 0x5A;
  static const providerId = 'xor-demo';
  @override
  String get id => providerId;

  // encrypt receives the plaintext and returns the wire ciphertext. It is also
  // responsible for stamping the AtKey's routing metadata. Use context.atClient
  // for anything you need to fetch to complete the operation — e.g. a
  // recipient's public key.
  @override
  Future<String> encrypt(
    CryptoContext context,
    AtKey atKey,
    String value,
  ) async {
    final cipher = utf8.encode(value).map((b) => b ^ _xorKey).toList();
    // appMetadata.providerId is SDK-owned routing; it must be this provider's
    // id so future reads route back here. Put any extra per-record info (e.g.
    // IV, key id) in appMetadata.additional – it travels with the record and
    // is visible to the atServer. isEncrypted marks the value as ciphertext.
    atKey.metadata.appMetadata = AppMetadata(
      providerId: id,
      additional: {'v': 1},
    );
    atKey.metadata.isEncrypted = true;
    return base64.encode(cipher);
  }

  // decrypt receives the wire ciphertext and returns the plaintext.
  @override
  Future<String> decrypt(
    CryptoContext context,
    AtKey atKey,
    String value,
  ) async {
    final plain = base64.decode(value).map((b) => b ^ _xorKey).toList();
    return utf8.decode(plain);
  }
}

// ---------------------------------------------------------------------------
// Step 2: Wire it up via AtClientPreference
//
// Pass a CryptoConfig with:
//   - defaultProviderId : the id of the provider used for new puts
//   - providers         : the provider instances to register on this client.
//                         The SDK calls initialize(context) on each before use.
//                         Supply a fresh instance per atSign if your provider
//                         holds per-atSign state. A read whose record names an
//                         unregistered provider throws CryptoProviderNotRegistered.
// ---------------------------------------------------------------------------
AtOnboardingPreference buildPreference() {
  return AtOnboardingPreference()
    ..crypto = CryptoConfig(
      defaultProviderId: XorCryptoProvider.providerId,
      providers: [XorCryptoProvider()],
    );
}

// ---------------------------------------------------------------------------
// Step 3: Use it – put and get work unchanged; encryption is transparent
// ---------------------------------------------------------------------------
void main(List<String> args) async {
  stdout.writeln('Custom crypto provider demo');

  final ap =
      CLIBase.createArgsParser(namespace: applicationNamespace)
        ..addOption(
          'role',
          abbr: 'R',
          mandatory: true,
          help: 'Role (writer / reader)',
        )
        ..addOption(
          'other-at-sign',
          abbr: 'O',
          help: 'The other atSign (required for writer)',
          defaultsTo: '',
        );

  late ArgResults ar;
  try {
    ar = ap.parse(args);
  } catch (e) {
    stderr.writeln(ap.usage);
    stderr.writeln('\n$e');
    exit(1);
  }

  final cli = await CLIBase.fromCommandLineArgs(
    args,
    parser: ap,
    preference: buildPreference(), // <-- inject crypto config here
  );
  final atClient = cli.atClient;

  final me = atClient.getCurrentAtSign()!.toAtsign();
  final other = ar['other-at-sign'].toString().trim();

  switch (ar['role'].toString().toLowerCase()) {
    case 'writer':
      if (other.isEmpty) {
        stderr.writeln('--other-at-sign is required for writer');
        exit(1);
      }
      final key =
          AtKey()
            ..key = 'secret'
            ..namespace = applicationNamespace
            ..sharedBy = me
            ..sharedWith = other.toAtsign();

      const plaintext = 'hello from the xor provider!';
      stdout.writeln('Writing key: @$other:${key.key}.${key.namespace}@$me');
      stdout.writeln('Writing: "$plaintext"');
      final putResult = await atClient.put(key, plaintext);
      stdout.writeln('put() returned: $putResult');

      // Read it back immediately to confirm it round-trips locally
      final verify = await atClient.get(key);
      stdout.writeln('Read-back metadata: ${verify.metadata}');
      stdout.writeln(
        'Read-back appMetadata: ${verify.metadata?.appMetadata?.toJson()}',
      );
      stdout.writeln('Read-back value: "${verify.value}"');

    case 'reader':
      if (other.isEmpty) {
        stderr.writeln('--other-at-sign is required for reader');
        exit(1);
      }
      // sharedBy = the writer, sharedWith = me (the reader)
      final key =
          AtKey()
            ..key = 'secret'
            ..namespace = applicationNamespace
            ..sharedBy = other.toAtsign()
            ..sharedWith = me;

      stdout.writeln('Reading key: @$me:${key.key}.${key.namespace}@$other');
      final result = await atClient.get(key);
      stdout.writeln('Decrypted value: "${result.value}"');

    default:
      stderr.writeln('Unknown role. Use --role writer or --role reader');
      exit(1);
  }

  exit(0);
}
