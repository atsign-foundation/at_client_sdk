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
class XorCryptoProvider implements CryptoProvider {
  static const _xorKey = 0x5A;
  static const providerId = 'xor-demo';
  @override
  String get id => providerId;

  // initialize() is called once by AtClientImpl after construction.
  // Fetch or derive your long-term key material here.
  @override
  Future<void> initialize(CryptoContext context) async {
    // context.atClient  – the fully-wired AtClient
    // context.atChops   – low-level RSA/AES primitives (nullable)
    // context.storage   – read/write keys to local or remote secondary
    stdout.writeln(
      '[XorCryptoProvider] initialized for ${context.currentAtSign}',
    );
  }

  @override
  Future<CryptoEncryptResult> encrypt(CryptoEncryptRequest request) async {
    final plainBytes = utf8.encode(request.plaintext.toString());
    final cipher = plainBytes.map((b) => b ^ _xorKey).toList();
    final encoded = base64.encode(cipher);
    return CryptoEncryptResult(
      ciphertext: encoded,
      // metadata.providerId is SDK-owned routing; it must match this provider's id.
      // Put any extra per-record info (e.g. IV, key ID) in metadata.additional –
      // it travels with the record as appMetadata and is visible to atServer.
      metadata: AppMetadata(providerId: id, additional: {'v': 1}),
    );
  }

  @override
  Future<CryptoDecryptResult> decrypt(CryptoDecryptRequest request) async {
    final cipher = base64.decode(request.ciphertext.toString());
    final plainBytes = cipher.map((b) => b ^ _xorKey).toList();
    return CryptoDecryptResult(plaintext: utf8.decode(plainBytes));
  }
}

// ---------------------------------------------------------------------------
// Step 2: Wire it up via AtClientPreference
//
// Pass a CryptoConfig with:
//   - defaultProviderId : the id of the provider used for new puts
//   - provider          : factory that receives a CryptoContext at init time
//   - policy            : (optional) handle unknown providers at read time
// ---------------------------------------------------------------------------
AtOnboardingPreference buildPreference() {
  return AtOnboardingPreference()
    ..crypto = CryptoConfig.singleProvider(
      defaultProviderId: XorCryptoProvider.providerId,
      // CryptoProviderFactory = FutureOr<CryptoProvider> Function(CryptoContext)
      provider: (context) => XorCryptoProvider(),
      // CryptoPolicy.onProviderNotFound is called when a stored record
      // references a provider that isn't registered yet (e.g. lazy loading).
      // Return CryptoFailureResolution.throwError() (default) or .retry().
      policy: const CryptoPolicy(),
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
