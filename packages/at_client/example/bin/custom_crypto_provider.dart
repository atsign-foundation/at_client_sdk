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

  // encrypt receives the plaintext and returns the wire ciphertext. The SDK
  // stamps appMetadata.providerId + isEncrypted for you — a provider only needs
  // to carry, in appMetadata.additional, anything its decrypt will need back
  // (here a format version). Use context.atClient to fetch what you need (e.g.
  // a recipient's public key). plaintext is opaque: for binary records it's a
  // Base2e15-encoded string, so treat it as bytes, not text.
  @override
  Future<String> encrypt(
    CryptoContext context,
    AtKey atKey,
    String plaintext,
  ) async {
    final cipher = utf8.encode(plaintext).map((b) => b ^ _xorKey).toList();
    atKey.metadata.appMetadata = AppMetadata(
      providerId: id,
      additional: {'v': 1},
    );
    return base64.encode(cipher);
  }

  // decrypt receives the wire ciphertext and returns the plaintext. Read back
  // the per-record data stored on encrypt from appMetadata.additional, and
  // throw an AtException subclass on failure so the SDK can chain diagnostics.
  @override
  Future<String> decrypt(
    CryptoContext context,
    AtKey atKey,
    String ciphertext,
  ) async {
    final version = atKey.metadata.appMetadata?.additional?['v'];
    if (version != 1) {
      throw AtDecryptionException('Unsupported xor-demo format: v$version');
    }
    final plain = base64.decode(ciphertext).map((b) => b ^ _xorKey).toList();
    return utf8.decode(plain);
  }
}

// ---------------------------------------------------------------------------
// Step 2: Wire it up via AtClientPreference
//
// Pass a CryptoConfig with:
//   - defaultProviderId : the id of the provider used for new puts
//   - providers         : the provider instances to register on this client.
//                         Supply a fresh instance per atSign only if your
//                         provider holds per-atSign state. A read whose record
//                         names an unregistered provider throws
//                         CryptoProviderNotRegistered.
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
      stdout.writeln('Writing key: ${key.toString()}');
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

      stdout.writeln('Reading key: ${key.toString()}');
      final result = await atClient.get(key);
      stdout.writeln('Decrypted value: "${result.value}"');

    default:
      stderr.writeln('Unknown role. Use --role writer or --role reader');
      exit(1);
  }

  exit(0);
}
