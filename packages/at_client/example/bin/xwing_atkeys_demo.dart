import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_chops/at_chops.dart';
import 'package:args/args.dart';
import 'package:cryptography/cryptography.dart' as crypto;

const _xwingAlgorithm = 'xwing-pure-dart';
const _pkamAlgorithm = 'rsa-2048-demo';
const _signingAlgorithm = 'ed25519-demo';
const _symmetricAlgorithm = 'aes-256-gcm-demo';
const _payloadAlgorithm = 'aes-256-gcm';
const _demoNamespace = 'xwingdemo';
const _defaultPayload = 'hello from the X-Wing crypto provider demo';
const _keyStoreDirectory = '.xwing_atkeys_demo';
const _xwingRotationWindow = Duration(seconds: 10);

final _createdAt = DateTime.utc(2026, 1, 1);
final _notAfter = DateTime.utc(2036, 1, 1);

Future<void> main(List<String> args) async {
  final argResults = _parseArgs(args);
  if (argResults == null) {
    return;
  }
  final plaintext = argResults['message'] as String;

  printTitle();

  final authProvider = AuthProvider();
  final keyStore = AtKeysSetFileStore(Directory(_keyStoreDirectory));
  final aliceState = await loadOrCreateKeySet(
    atSign: '@alice',
    authProvider: authProvider,
    keyStore: keyStore,
  );
  final bobState = await loadOrCreateKeySet(
    atSign: '@bob',
    authProvider: authProvider,
    keyStore: keyStore,
  );
  final aliceKeys = aliceState.keySet;
  final bobKeys = bobState.keySet;
  final keyDirectory = [aliceKeys, bobKeys];
  final aliceXWingProvider = XWingProvider(
    ownerKeys: aliceKeys,
    keyDirectory: keyDirectory,
  );
  final bobXWingProvider = XWingProvider(
    ownerKeys: bobKeys,
    keyDirectory: keyDirectory,
  );

  printStartupStates([aliceState, bobState]);
  printKeySet(aliceKeys);
  printKeySet(bobKeys);

  assertLookups(aliceKeys);
  assertLookups(bobKeys);

  final atKey =
      AtKey()
        ..key = 'secret'
        ..namespace = _demoNamespace
        ..sharedBy = aliceKeys.atsign.toString()
        ..sharedWith = bobKeys.atsign.toString();

  final encrypted = await aliceXWingProvider.encrypt(
    CryptoEncryptRequest(atKey: atKey, plaintext: plaintext),
  );
  final decrypted = await bobXWingProvider.decrypt(
    CryptoDecryptRequest(
      atKey: atKey,
      ciphertext: encrypted.ciphertext,
      metadata: encrypted.metadata,
    ),
  );

  if (decrypted.plaintext != plaintext) {
    throw StateError('X-Wing payload did not decrypt to the original value');
  }

  printRoundTripSummary(encrypted: encrypted, decrypted: decrypted);
}

Future<KeySetStartupState> loadOrCreateKeySet({
  required String atSign,
  required AuthProvider authProvider,
  required AtKeysSetFileStore keyStore,
}) async {
  final stored = await keyStore.read(atSign);
  late final AtKeysSet keySet;
  late final XWingRotationResult rotation;
  if (stored == null) {
    keySet = await authProvider.createKeySet(atSign);
    rotation = XWingRotationResult.generated(_activeXWingKey(keySet));
    await keyStore.write(keySet);
  } else {
    keySet = stored;
    rotation = await authProvider.rotateExpiredXWingKey(keySet);
    if (rotation.persistRequired) {
      await keyStore.write(keySet);
    }
  }

  return KeySetStartupState(
    keySet: keySet,
    storagePath: keyStore.pathFor(atSign),
    loadedFromDisk: stored != null,
    rotation: rotation,
  );
}

ArgResults? _parseArgs(List<String> args) {
  final parser =
      ArgParser()
        ..addFlag(
          'help',
          abbr: 'h',
          negatable: false,
          help: 'Print this usage information.',
        )
        ..addOption(
          'message',
          abbr: 'm',
          defaultsTo: _defaultPayload,
          help: 'Message payload to encrypt and decrypt.',
        );

  late ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return null;
  }

  if (results['help'] as bool) {
    stdout.writeln(parser.usage);
    return null;
  }
  return results;
}

class AuthProvider {
  Future<AtKeysSet> createKeySet(String atSign) async {
    final owner = atSign.toAtsign();
    final label = atSign.replaceFirst('@', '');
    final keySet = AtKeysSet(
      atsign: owner,
      enrollmentId: '$label-demo-enrollment',
      asymmetricKeys: [],
      symmetricKeys: [],
    );

    await seedKeys(keySet);
    return keySet;
  }

  Future<void> seedKeys(AtKeysSet keySet) async {
    final label = _labelFor(keySet.atsign);
    final xwingKeyPair = await XWingPureDartAlgo.instance.generateKeyPair();

    keySet.addKeys([
      createPkamKey(label),
      createSigningKey(label),
      createXWingEncryptionKey(label, xwingKeyPair),
      createSelfEncryptionKey(label),
      createApkamSymmetricKey(label),
    ]);
  }

  Future<XWingRotationResult> rotateExpiredXWingKey(AtKeysSet keySet) async {
    final activeKeyIndex = keySet.asymmetricKeys.indexWhere(_isActiveXWingKey);
    if (activeKeyIndex == -1) {
      final replacement = await createFreshXWingEncryptionKey(keySet);
      keySet.addKey(replacement);
      return XWingRotationResult.generated(replacement);
    }

    final activeKey = keySet.asymmetricKeys[activeKeyIndex];
    if (!_isExpired(activeKey.notAfter)) {
      return XWingRotationResult.reused(activeKey);
    }

    final retiredKey = _copyAsymmetricKey(
      activeKey,
      status: 'retired',
      operations: const ['retired'],
    );
    keySet.asymmetricKeys[activeKeyIndex] = retiredKey;

    final replacement = await createFreshXWingEncryptionKey(keySet);
    keySet.addKey(replacement);
    return XWingRotationResult.rotated(
      retiredKey: retiredKey,
      activeKey: replacement,
    );
  }

  AtAsymmetricKey createPkamKey(String label) {
    return _asymmetricKey(
      pairId: '$label-pkam-v1',
      purpose: KeyPurposes.pkam,
      algorithm: _pkamAlgorithm,
      publicKey: _bytes('$label-pkam-public'),
      privateKey: _bytes('$label-pkam-private'),
      operations: const ['auth'],
      privateKeyProtectionRef: '$label-self-v1',
    );
  }

  AtAsymmetricKey createSigningKey(String label) {
    return _asymmetricKey(
      pairId: '$label-signing-v1',
      purpose: KeyPurposes.signing,
      algorithm: _signingAlgorithm,
      publicKey: _bytes('$label-signing-public'),
      privateKey: _bytes('$label-signing-private'),
      operations: const ['sign', 'verify'],
      privateKeyProtectionRef: '$label-self-v1',
    );
  }

  AtAsymmetricKey createXWingEncryptionKey(
    String label,
    ({Uint8List publicKey, Uint8List secretKey}) keyPair, {
    String? pairId,
    DateTime? createdAt,
    DateTime? notAfter,
  }) {
    pairId ??= '$label-xwing-enc-v1';
    createdAt ??= DateTime.now().toUtc();
    notAfter ??= createdAt.add(_xwingRotationWindow);
    return _asymmetricKey(
      pairId: pairId,
      purpose: KeyPurposes.encryption,
      algorithm: _xwingAlgorithm,
      publicKey: AtBytes(keyPair.publicKey),
      privateKey: AtBytes(keyPair.secretKey),
      operations: const ['encrypt', 'decrypt'],
      privateKeyProtectionRef: '$label-self-v1',
      createdAt: createdAt,
      notAfter: notAfter,
    );
  }

  Future<AtAsymmetricKey> createFreshXWingEncryptionKey(
    AtKeysSet keySet,
  ) async {
    final label = _labelFor(keySet.atsign);
    final now = DateTime.now().toUtc();
    final keyPair = await XWingPureDartAlgo.instance.generateKeyPair();
    return createXWingEncryptionKey(
      label,
      keyPair,
      pairId: '$label-xwing-enc-${now.microsecondsSinceEpoch}',
      createdAt: now,
      notAfter: now.add(_xwingRotationWindow),
    );
  }

  AtSymmetricKey createSelfEncryptionKey(String label) {
    return _symmetricKey(
      id: '$label-self-v1',
      purpose: KeyPurposes.selfEncryption,
      bytes: _fixedLengthBytes('$label-self-encryption-key', 32),
      operations: const ['wrap', 'unwrap'],
    );
  }

  AtSymmetricKey createApkamSymmetricKey(String label) {
    return _symmetricKey(
      id: '$label-apkam-symmetric-v1',
      purpose: KeyPurposes.apkamSymmetric,
      bytes: _fixedLengthBytes('$label-apkam-symmetric-key', 32),
      operations: const ['auth'],
      protectionRef: '$label-self-v1',
    );
  }
}

class AtKeysSetFileStore {
  final Directory directory;

  AtKeysSetFileStore(this.directory);

  String pathFor(String atSign) {
    final label = atSign.toAtsign().toString().replaceFirst('@', '');
    return '${directory.path}/$label.keys.json';
  }

  Future<AtKeysSet?> read(String atSign) async {
    final file = File(pathFor(atSign));
    if (!file.existsSync()) {
      return null;
    }
    final json = jsonDecode(await file.readAsString());
    if (json is! Map<String, dynamic>) {
      throw FormatException('Expected AtKeysSet JSON object in ${file.path}');
    }
    return _atKeysSetFromJson(json);
  }

  Future<void> write(AtKeysSet keySet) async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    final file = File(pathFor(keySet.atsign.toString()));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(_atKeysSetToJson(keySet))}\n');
  }
}

class KeySetStartupState {
  final AtKeysSet keySet;
  final String storagePath;
  final bool loadedFromDisk;
  final XWingRotationResult rotation;

  const KeySetStartupState({
    required this.keySet,
    required this.storagePath,
    required this.loadedFromDisk,
    required this.rotation,
  });
}

class XWingRotationResult {
  final bool persistRequired;
  final String action;
  final AtAsymmetricKey? retiredKey;
  final AtAsymmetricKey activeKey;

  const XWingRotationResult._({
    required this.persistRequired,
    required this.action,
    required this.retiredKey,
    required this.activeKey,
  });

  factory XWingRotationResult.reused(AtAsymmetricKey activeKey) {
    return XWingRotationResult._(
      persistRequired: false,
      action: 'reused',
      retiredKey: null,
      activeKey: activeKey,
    );
  }

  factory XWingRotationResult.generated(AtAsymmetricKey activeKey) {
    return XWingRotationResult._(
      persistRequired: true,
      action: 'generated',
      retiredKey: null,
      activeKey: activeKey,
    );
  }

  factory XWingRotationResult.rotated({
    required AtAsymmetricKey retiredKey,
    required AtAsymmetricKey activeKey,
  }) {
    return XWingRotationResult._(
      persistRequired: true,
      action: 'rotated',
      retiredKey: retiredKey,
      activeKey: activeKey,
    );
  }
}

class XWingProvider extends CryptoProvider {
  static const providerId = 'xwing-demo';

  final AtKeysSet ownerKeys;
  final Map<String, AtKeysSet> _keyDirectory;
  final crypto.AesGcm _payloadCipher = crypto.AesGcm.with256bits();

  XWingProvider({
    required this.ownerKeys,
    required Iterable<AtKeysSet> keyDirectory,
  }) : _keyDirectory = {
         for (final keySet in keyDirectory)
           keySet.atsign.toString().toLowerCase(): keySet,
       };

  @override
  String get id => providerId;

  @override
  Future<CryptoEncryptResult> encrypt(CryptoEncryptRequest request) async {
    final recipientAtSign = request.atKey.sharedWith;
    if (recipientAtSign == null || recipientAtSign.isEmpty) {
      throw StateError('X-Wing demo encryption requires atKey.sharedWith');
    }
    final recipientKeys = _lookupKeySet(recipientAtSign);
    final kemResult = await encapsulateForRecipient(
      recipientKeys: recipientKeys,
    );
    final nonce = _payloadCipher.newNonce();
    final secretBox = await _payloadCipher.encrypt(
      utf8.encode(request.plaintext.toString()),
      secretKey: crypto.SecretKey(kemResult.sharedSecret),
      nonce: nonce,
    );

    return CryptoEncryptResult(
      ciphertext: base64Encode(secretBox.cipherText),
      metadata: AppMetadata(
        providerId: id,
        additional: {
          'payloadAlgorithm': _payloadAlgorithm,
          'kemAlgorithm': _xwingAlgorithm,
          'recipientKeyPairId': kemResult.recipientKeyPairId,
          'kemCiphertext': base64Encode(kemResult.ciphertext),
          'kemCiphertextLength': kemResult.ciphertext.length,
          'nonce': base64Encode(secretBox.nonce),
          'mac': base64Encode(secretBox.mac.bytes),
        },
      ),
    );
  }

  @override
  Future<CryptoDecryptResult> decrypt(CryptoDecryptRequest request) async {
    if (request.metadata.providerId != id) {
      throw StateError(
        'Metadata provider ${request.metadata.providerId} is not $id',
      );
    }
    final additional = request.metadata.additional;
    if (additional == null) {
      throw StateError('Missing X-Wing demo metadata');
    }
    _validateMetadataAlgorithm(
      additional,
      key: 'payloadAlgorithm',
      expected: _payloadAlgorithm,
    );
    _validateMetadataAlgorithm(
      additional,
      key: 'kemAlgorithm',
      expected: _xwingAlgorithm,
    );
    final recipientKeyPairId = _requiredMetadataString(
      additional,
      'recipientKeyPairId',
    );
    final kemCiphertext = base64Decode(
      _requiredMetadataString(additional, 'kemCiphertext'),
    );
    final sharedSecret = await decapsulateForOwner(
      ownerKeys: ownerKeys,
      pairId: recipientKeyPairId,
      ciphertext: Uint8List.fromList(kemCiphertext),
    );
    final payloadCiphertext = base64Decode(request.ciphertext.toString());
    final secretBox = crypto.SecretBox(
      payloadCiphertext,
      nonce: base64Decode(_requiredMetadataString(additional, 'nonce')),
      mac: crypto.Mac(base64Decode(_requiredMetadataString(additional, 'mac'))),
    );
    final plaintextBytes = await _payloadCipher.decrypt(
      secretBox,
      secretKey: crypto.SecretKey(sharedSecret),
    );

    return CryptoDecryptResult(plaintext: utf8.decode(plaintextBytes));
  }

  Future<XWingKemResult> encapsulateForRecipient({
    required AtKeysSet recipientKeys,
  }) async {
    final recipientKey = selectRecipientEncryptionKey(
      recipientKeys: recipientKeys,
    );
    final result = await XWingPureDartAlgo.instance.encapsulate(
      recipientKey.publicKey.bytes,
    );

    return XWingKemResult(
      recipientKeyPairId: recipientKey.pairId,
      ciphertext: result.ciphertext,
      sharedSecret: result.sharedSecret,
    );
  }

  Future<Uint8List> decapsulateForOwner({
    required AtKeysSet ownerKeys,
    required String pairId,
    required Uint8List ciphertext,
  }) {
    final ownerKey = selectOwnerDecryptionKey(
      ownerKeys: ownerKeys,
      pairId: pairId,
    );
    _validateCiphertextLength(ciphertext, ownerKeys.atsign);
    return XWingPureDartAlgo.instance.decapsulate(
      ownerKey.privateKey.bytes,
      ciphertext,
    );
  }

  AtAsymmetricKey selectRecipientEncryptionKey({
    required AtKeysSet recipientKeys,
  }) {
    final selected = _selectXWingKey(
      keySet: recipientKeys,
      operation: 'encrypt',
    );
    _validatePublicKeyLength(selected, recipientKeys.atsign);
    return selected;
  }

  AtAsymmetricKey selectOwnerDecryptionKey({
    required AtKeysSet ownerKeys,
    required String pairId,
  }) {
    final selected = ownerKeys.getKeyPair(pairId);
    if (selected == null) {
      throw StateError(
        'Missing X-Wing key pair $pairId for ${ownerKeys.atsign}',
      );
    }
    _validateXWingKey(key: selected, keySet: ownerKeys, operation: 'decrypt');
    _validatePrivateKeyLength(selected, ownerKeys.atsign);
    return selected;
  }

  AtAsymmetricKey _selectXWingKey({
    required AtKeysSet keySet,
    required String operation,
  }) {
    final matches = keySet.asymmetricKeys
        .where((key) {
          return key.purpose == KeyPurposes.encryption &&
              key.algorithm == _xwingAlgorithm &&
              key.status == 'active' &&
              key.operations.contains(operation) &&
              !_isExpired(key.notAfter);
        })
        .toList(growable: false);

    if (matches.isEmpty) {
      throw StateError(
        'No active X-Wing key for ${keySet.atsign} supports $operation',
      );
    }
    if (matches.length > 1) {
      throw StateError(
        'Multiple active X-Wing keys for ${keySet.atsign} support $operation',
      );
    }

    return matches.single;
  }

  void _validateXWingKey({
    required AtAsymmetricKey key,
    required AtKeysSet keySet,
    required String operation,
  }) {
    if (key.purpose != KeyPurposes.encryption) {
      throw StateError('${key.pairId} is not an encryption key');
    }
    if (key.algorithm != _xwingAlgorithm) {
      throw StateError('${key.pairId} uses ${key.algorithm}, not X-Wing');
    }
    if (key.status != 'active') {
      throw StateError('${key.pairId} is not active');
    }
    if (!key.operations.contains(operation)) {
      throw StateError('${key.pairId} does not support $operation');
    }
    if (_isExpired(key.notAfter)) {
      throw StateError('${key.pairId} expired at ${key.notAfter}');
    }
    _validateProtectionReference(key, keySet);
  }

  void _validateProtectionReference(AtAsymmetricKey key, AtKeysSet keySet) {
    final protection = key.privateKeyProtection;
    if (protection == null) {
      throw StateError('${key.pairId} is missing private key protection');
    }
    final wrappingKey = keySet.getSymmetricKey(protection.keyRef);
    if (wrappingKey == null) {
      throw StateError(
        '${key.pairId} references missing protection key ${protection.keyRef}',
      );
    }
    if (wrappingKey.purpose != KeyPurposes.selfEncryption) {
      throw StateError('${protection.keyRef} is not a self-encryption key');
    }
    if (!wrappingKey.operations.contains('unwrap')) {
      throw StateError('${protection.keyRef} cannot unwrap protected keys');
    }
  }

  void _validatePublicKeyLength(AtAsymmetricKey key, Atsign owner) {
    if (key.publicKey.bytes.length != XWingPureDartAlgo.publicKeyLength) {
      throw StateError('Unexpected X-Wing public key length for $owner');
    }
  }

  void _validatePrivateKeyLength(AtAsymmetricKey key, Atsign owner) {
    if (key.privateKey.bytes.length != XWingPureDartAlgo.seedLength) {
      throw StateError('Unexpected X-Wing private key length for $owner');
    }
  }

  void _validateCiphertextLength(Uint8List ciphertext, Atsign owner) {
    if (ciphertext.length != XWingPureDartAlgo.ciphertextLength) {
      throw StateError('Unexpected X-Wing ciphertext length for $owner');
    }
  }

  AtKeysSet _lookupKeySet(String atSign) {
    final normalized = atSign.toAtsign().toString().toLowerCase();
    final keySet = _keyDirectory[normalized];
    if (keySet == null) {
      throw StateError('No demo key set found for $normalized');
    }
    return keySet;
  }
}

class XWingKemResult {
  final String recipientKeyPairId;
  final Uint8List ciphertext;
  final Uint8List sharedSecret;

  const XWingKemResult({
    required this.recipientKeyPairId,
    required this.ciphertext,
    required this.sharedSecret,
  });
}

AtAsymmetricKey _asymmetricKey({
  required String pairId,
  required String purpose,
  required String algorithm,
  required AtBytes publicKey,
  required AtBytes privateKey,
  required List<String> operations,
  required String privateKeyProtectionRef,
  DateTime? createdAt,
  DateTime? notAfter,
}) {
  return AtAsymmetricKey(
    pairId: pairId,
    purpose: purpose,
    algorithm: algorithm,
    fingerprint: KeyFingerprint(
      algorithm: 'demo-fingerprint',
      value: _bytes('$pairId:$algorithm'),
    ),
    publicKey: publicKey,
    privateKey: privateKey,
    publicKeyProtection: KeyProtection(
      keyRef: 'public-demo-ref',
      algorithm: 'none-demo',
      iv: 'public-demo-iv',
    ),
    privateKeyProtection: KeyProtection(
      keyRef: privateKeyProtectionRef,
      algorithm: _symmetricAlgorithm,
      iv: '$pairId-private-iv',
    ),
    status: 'active',
    createdAt: createdAt ?? _createdAt,
    notAfter: notAfter ?? _notAfter,
    operations: operations,
  );
}

AtSymmetricKey _symmetricKey({
  required String id,
  required String purpose,
  required AtBytes bytes,
  required List<String> operations,
  String? protectionRef,
}) {
  return AtSymmetricKey(
    id: id,
    purpose: purpose,
    algorithm: _symmetricAlgorithm,
    bytes: bytes,
    protection:
        protectionRef == null
            ? null
            : KeyProtection(
              keyRef: protectionRef,
              algorithm: _symmetricAlgorithm,
              iv: '$id-protection-iv',
            ),
    status: 'active',
    createdAt: _createdAt,
    notAfter: _notAfter,
    operations: operations,
  );
}

void printTitle() {
  _rule('=');
  stdout.writeln('X-Wing AtKeysSet Demo');
  stdout.writeln(
    'File-backed keys, 10-second KEM rotation, CryptoProvider round-trip',
  );
  stdout.writeln('No AtClient, onboarding, sync, or atServer is used.');
  _rule('=');
  stdout.writeln('');
}

void printStartupStates(List<KeySetStartupState> states) {
  _section('Startup');
  _printTable(
    widths: const [8, 9, 9, 35, 35, 20],
    rows: [
      const ['atSign', 'source', 'xwing', 'active', 'retired', 'expires'],
      for (final state in states)
        [
          state.keySet.atsign.toString(),
          state.loadedFromDisk ? 'loaded' : 'generated',
          state.rotation.action,
          state.rotation.activeKey.pairId,
          state.rotation.retiredKey?.pairId ?? '-',
          _timeSummary(state.rotation.activeKey.notAfter),
        ],
    ],
  );
  stdout.writeln('');
}

void printKeySet(AtKeysSet keySet) {
  _section('Key Inventory ${keySet.atsign}');
  stdout.writeln('enrollmentId: ${keySet.enrollmentId}');
  _printTable(
    widths: const [5, 35, 15, 17, 8, 16, 9, 9, 20],
    rows: [
      const [
        'type',
        'id',
        'purpose',
        'algorithm',
        'status',
        'operations',
        'public',
        'private',
        'expires',
      ],
      for (final key in keySet.asymmetricKeys)
        [
          'asym',
          key.pairId,
          key.purpose,
          key.algorithm,
          key.status ?? '-',
          key.operations.join(','),
          '${key.publicKey.bytes.length}b',
          '${key.privateKey.bytes.length}b',
          _timeSummary(key.notAfter),
        ],
      for (final key in keySet.symmetricKeys)
        [
          'sym',
          key.id,
          key.purpose,
          key.algorithm,
          key.status ?? '-',
          key.operations.join(','),
          '-',
          '${key.bytes.bytes.length}b',
          _timeSummary(key.notAfter),
        ],
    ],
  );
  stdout.writeln('');
}

void printRoundTripSummary({
  required CryptoEncryptResult encrypted,
  required CryptoDecryptResult decrypted,
}) {
  final metadata = encrypted.metadata.additional!;
  _section('CryptoProvider Round Trip');
  _printTable(
    widths: const [24, 56],
    rows: [
      ['providerId', encrypted.metadata.providerId],
      ['recipientKeyPairId', metadata['recipientKeyPairId'].toString()],
      ['kemCiphertextLength', metadata['kemCiphertextLength'].toString()],
      ['payloadCiphertextLength', encrypted.ciphertext.length.toString()],
      ['decryptedPlaintext', decrypted.plaintext.toString()],
    ],
  );
  stdout.writeln('');
}

void assertLookups(AtKeysSet keySet) {
  final label = _labelFor(keySet.atsign);
  final xwingKey = keySet.getKeyPair('$label-xwing-enc-v1');
  final selfKey = keySet.getSymmetricKey('$label-self-v1');

  if (xwingKey == null) {
    throw StateError('Missing X-Wing key for ${keySet.atsign}');
  }
  if (selfKey == null) {
    throw StateError('Missing self-encryption key for ${keySet.atsign}');
  }
  if (xwingKey.publicKey.bytes.length != XWingPureDartAlgo.publicKeyLength) {
    throw StateError(
      'Unexpected X-Wing public key length for ${keySet.atsign}',
    );
  }
  if (xwingKey.privateKey.bytes.length != XWingPureDartAlgo.seedLength) {
    throw StateError(
      'Unexpected X-Wing private key length for ${keySet.atsign}',
    );
  }
}

String _labelFor(Atsign atSign) {
  return atSign.toString().replaceFirst('@', '');
}

bool _isActiveXWingKey(AtAsymmetricKey key) {
  return key.purpose == KeyPurposes.encryption &&
      key.algorithm == _xwingAlgorithm &&
      key.status == 'active';
}

AtAsymmetricKey _activeXWingKey(AtKeysSet keySet) {
  final matches = keySet.asymmetricKeys.where(_isActiveXWingKey).toList();
  if (matches.length != 1) {
    throw StateError(
      'Expected exactly one active X-Wing key for ${keySet.atsign}, '
      'found ${matches.length}',
    );
  }
  return matches.single;
}

bool _isExpired(DateTime? notAfter) {
  return notAfter != null && !notAfter.isAfter(DateTime.now().toUtc());
}

AtAsymmetricKey _copyAsymmetricKey(
  AtAsymmetricKey key, {
  String? status,
  List<String>? operations,
}) {
  return AtAsymmetricKey(
    pairId: key.pairId,
    purpose: key.purpose,
    algorithm: key.algorithm,
    fingerprint: key.fingerprint,
    publicKey: key.publicKey,
    privateKey: key.privateKey,
    publicKeyProtection: key.publicKeyProtection,
    privateKeyProtection: key.privateKeyProtection,
    status: status ?? key.status,
    createdAt: key.createdAt,
    notAfter: key.notAfter,
    operations: operations ?? key.operations,
  );
}

AtBytes _bytes(String value) {
  return AtBytes(Uint8List.fromList(value.codeUnits));
}

AtBytes _fixedLengthBytes(String seed, int length) {
  final bytes = Uint8List(length);
  final seedBytes = seed.codeUnits;
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = seedBytes[i % seedBytes.length];
  }
  return AtBytes(bytes);
}

Map<String, dynamic> _atKeysSetToJson(AtKeysSet keySet) {
  return {
    'atsign': keySet.atsign.toString(),
    'enrollmentId': keySet.enrollmentId,
    'asymmetricKeys': keySet.asymmetricKeys.map(_asymmetricKeyToJson).toList(),
    'symmetricKeys': keySet.symmetricKeys.map(_symmetricKeyToJson).toList(),
  };
}

AtKeysSet _atKeysSetFromJson(Map<String, dynamic> json) {
  return AtKeysSet(
    atsign: _requiredString(json, 'atsign').toAtsign(),
    enrollmentId: json['enrollmentId'] as String?,
    asymmetricKeys:
        _jsonList(
          json,
          'asymmetricKeys',
        ).map((entry) => _asymmetricKeyFromJson(_jsonMap(entry))).toList(),
    symmetricKeys:
        _jsonList(
          json,
          'symmetricKeys',
        ).map((entry) => _symmetricKeyFromJson(_jsonMap(entry))).toList(),
  );
}

Map<String, dynamic> _asymmetricKeyToJson(AtAsymmetricKey key) {
  return {
    'pairId': key.pairId,
    'purpose': key.purpose,
    'algorithm': key.algorithm,
    'fingerprint': _fingerprintToJson(key.fingerprint),
    'publicKey': key.publicKey.toString(),
    'privateKey': key.privateKey.toString(),
    'publicKeyProtection': _protectionToJson(key.publicKeyProtection),
    'privateKeyProtection': _protectionToJson(key.privateKeyProtection),
    'status': key.status,
    'createdAt': key.createdAt?.toIso8601String(),
    'notAfter': key.notAfter?.toIso8601String(),
    'operations': key.operations,
  };
}

AtAsymmetricKey _asymmetricKeyFromJson(Map<String, dynamic> json) {
  return AtAsymmetricKey(
    pairId: _requiredString(json, 'pairId'),
    purpose: _requiredString(json, 'purpose'),
    algorithm: _requiredString(json, 'algorithm'),
    fingerprint: _fingerprintFromJson(json['fingerprint']),
    publicKey: AtBytes.fromString(_requiredString(json, 'publicKey')),
    privateKey: AtBytes.fromString(_requiredString(json, 'privateKey')),
    publicKeyProtection: _protectionFromJson(json['publicKeyProtection']),
    privateKeyProtection: _protectionFromJson(json['privateKeyProtection']),
    status: json['status'] as String?,
    createdAt: _dateTimeFromJson(json['createdAt']),
    notAfter: _dateTimeFromJson(json['notAfter']),
    operations: _stringList(json['operations']),
  );
}

Map<String, dynamic> _symmetricKeyToJson(AtSymmetricKey key) {
  return {
    'id': key.id,
    'purpose': key.purpose,
    'algorithm': key.algorithm,
    'bytes': key.bytes.toString(),
    'protection': _protectionToJson(key.protection),
    'status': key.status,
    'createdAt': key.createdAt?.toIso8601String(),
    'notAfter': key.notAfter?.toIso8601String(),
    'operations': key.operations,
  };
}

AtSymmetricKey _symmetricKeyFromJson(Map<String, dynamic> json) {
  return AtSymmetricKey(
    id: _requiredString(json, 'id'),
    purpose: _requiredString(json, 'purpose'),
    algorithm: _requiredString(json, 'algorithm'),
    bytes: AtBytes.fromString(_requiredString(json, 'bytes')),
    protection: _protectionFromJson(json['protection']),
    status: json['status'] as String?,
    createdAt: _dateTimeFromJson(json['createdAt']),
    notAfter: _dateTimeFromJson(json['notAfter']),
    operations: _stringList(json['operations']),
  );
}

Map<String, dynamic>? _fingerprintToJson(KeyFingerprint? fingerprint) {
  if (fingerprint == null) {
    return null;
  }
  return {
    'algorithm': fingerprint.algorithm,
    'value': fingerprint.value.toString(),
  };
}

KeyFingerprint? _fingerprintFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  final json = _jsonMap(value);
  return KeyFingerprint(
    algorithm: _requiredString(json, 'algorithm'),
    value: AtBytes.fromString(_requiredString(json, 'value')),
  );
}

Map<String, dynamic>? _protectionToJson(KeyProtection? protection) {
  if (protection == null) {
    return null;
  }
  return {
    'keyRef': protection.keyRef,
    'algorithm': protection.algorithm,
    'iv': protection.iv,
  };
}

KeyProtection? _protectionFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  final json = _jsonMap(value);
  return KeyProtection(
    keyRef: _requiredString(json, 'keyRef'),
    algorithm: _requiredString(json, 'algorithm'),
    iv: _requiredString(json, 'iv'),
  );
}

List<Object?> _jsonList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is List) {
    return value;
  }
  throw FormatException('Expected list field $key');
}

Map<String, dynamic> _jsonMap(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const FormatException('Expected JSON object');
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('Expected non-empty string field $key');
}

List<String> _stringList(Object? value) {
  if (value == null) {
    return const [];
  }
  if (value is List) {
    return value.map((entry) => entry.toString()).toList(growable: false);
  }
  throw const FormatException('Expected string list');
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.parse(value).toUtc();
  }
  throw const FormatException('Expected ISO-8601 date string');
}

void _section(String title) {
  stdout.writeln(title);
  stdout.writeln(_repeat('-', title.length));
}

void _rule(String char) {
  stdout.writeln(_repeat(char, 78));
}

void _printTable({
  required List<int> widths,
  required List<List<String>> rows,
}) {
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    stdout.writeln(_formatRow(row, widths));
    if (i == 0) {
      stdout.writeln(_formatSeparator(widths));
    }
  }
}

String _formatRow(List<String> row, List<int> widths) {
  return [
    for (var i = 0; i < widths.length; i++) _cell(row[i], widths[i]),
  ].join('  ');
}

String _formatSeparator(List<int> widths) {
  return [for (final width in widths) _repeat('-', width)].join('  ');
}

String _cell(String value, int width) {
  if (value.length <= width) {
    return value.padRight(width);
  }
  if (width <= 1) {
    return value.substring(0, width);
  }
  return '${value.substring(0, width - 1)}~';
}

String _timeSummary(DateTime? value) {
  if (value == null) {
    return '-';
  }
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')} '
      '${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')}:'
      '${utc.second.toString().padLeft(2, '0')}Z';
}

String _repeat(String value, int count) {
  return List.filled(count, value).join();
}

String _requiredMetadataString(Map<String, dynamic> metadata, String key) {
  final value = metadata[key];
  if (value is! String || value.isEmpty) {
    throw StateError('Missing X-Wing metadata field $key');
  }
  return value;
}

void _validateMetadataAlgorithm(
  Map<String, dynamic> metadata, {
  required String key,
  required String expected,
}) {
  final actual = _requiredMetadataString(metadata, key);
  if (actual != expected) {
    throw StateError('Unsupported $key $actual; expected $expected');
  }
}
