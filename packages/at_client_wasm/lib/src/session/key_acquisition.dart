import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';

import '../keys/envelope_exceptions.dart';
import '../keys/key_bytes_store.dart';
import '../keys/key_envelope.dart';
import '../keys/passkey_kek.dart';
import '../keys/passkey_port.dart';
import '../keys/unlock_secret.dart';
import '../keys/web_at_keys_io.dart';
import 'server_copy.dart';

/// The keys a session runs on. [prf] is set only when they are held in the
/// device's [KeyBytesStore] under a passkey, and is the secret [heal] adds to
/// the server copy.
typedef AcquiredKeys = ({AtKeysIo keysIo, PrfSecret? prf});

/// Opens [atSign]'s envelope — the device's copy in [store], else the server
/// copy of [app] — with a passkey, falling back to [promptPassphrase].
///
/// After a passphrase open a passkey is registered and its unlock added to
/// the device's copy. When registration yields no PRF secret, the keys are
/// held in memory only and nothing is written.
///
/// Never writes the server copy; [heal] does. Throws [StateError] when
/// neither copy exists, and the codec's exceptions when the passphrase does
/// not open the envelope.
Future<AcquiredKeys> acquireKeys({
  required String atSign,
  required String app,
  required KeyBytesStore store,
  required PasskeyKek kek,
  required ServerCopyReader server,
  required Future<PassphraseSecret> Function(String atSign) promptPassphrase,
  KeyEnvelopeCodec codec = const KeyEnvelopeCodec(),
  CredentialHintStore? hintStore,
}) async {
  final local = await store.get(atSign);
  final bytes = local ??
      await server.fetch(atSign, app) ??
      (throw StateError('$atSign has no keys on this device and no server '
          'copy for $app'));
  final hint = local == null ? null : await hintStore?.credentialId(atSign);

  final unlocked = await _openWithPasskey(atSign, bytes, kek, codec, hint);
  if (unlocked != null) {
    if (local == null) await store.put(atSign, bytes);
    if (hint == null) {
      await hintStore?.putCredentialId(atSign, unlocked.credentialId);
    }
    return _held(store, unlocked.secret, codec);
  }

  final passphrase = await promptPassphrase(atSign);
  final opened = await codec.open(atSign, bytes, passphrase);
  final ({Uint8List credentialId, PrfSecret secret}) registered;
  try {
    registered = await kek.register(atSign);
  } on PrfUnavailableException {
    return _inMemory(atSign, bytes, passphrase, codec);
  } on PasskeyCeremonyException {
    return _inMemory(atSign, bytes, passphrase, codec);
  }
  await store.put(atSign, await opened.withUnlock(registered.secret));
  await hintStore?.putCredentialId(atSign, registered.credentialId);
  return _held(store, registered.secret, codec);
}

/// What [heal] found, and whether it wrote the server copy.
enum HealOutcome {
  /// The server copy lacked the unlock and now holds it.
  healed,

  /// The server copy already opens with the unlock; nothing written.
  alreadyPresent,

  /// The server and device copies are sealed under different content keys;
  /// nothing written.
  contentKeyMismatch,

  /// The device or server copy is missing; nothing written.
  missingCopy,
}

/// Adds the [prf] unlock in [store]'s copy of [atSign]'s envelope to the
/// server copy of [app] when the server copy lacks it.
///
/// Writes only on [HealOutcome.healed].
Future<HealOutcome> heal({
  required String atSign,
  required String app,
  required KeyBytesStore store,
  required ServerCopy server,
  required PrfSecret prf,
  KeyEnvelopeCodec codec = const KeyEnvelopeCodec(),
}) async {
  final serverBytes = await server.fetch(atSign, app);
  final localBytes = await store.get(atSign);
  if (serverBytes == null || localBytes == null) {
    return HealOutcome.missingCopy;
  }
  if (await _opens(atSign, serverBytes, prf, codec)) {
    return HealOutcome.alreadyPresent;
  }

  final opened = await codec.open(atSign, localBytes, prf);
  final Uint8List merged;
  try {
    merged = await opened.mergeUnlocksFrom(serverBytes);
  } on EnvelopeContentKeyMismatchException {
    return HealOutcome.contentKeyMismatch;
  }
  await server.put(atSign, app, merged);
  return HealOutcome.healed;
}

AcquiredKeys _held(
        KeyBytesStore store, PrfSecret prf, KeyEnvelopeCodec codec) =>
    (keysIo: WebAtKeysIo(store, prf, codec: codec), prf: prf);

Future<AcquiredKeys> _inMemory(String atSign, Uint8List bytes,
    PassphraseSecret passphrase, KeyEnvelopeCodec codec) async {
  final memory = InMemoryKeyBytesStore();
  await memory.put(atSign, bytes);
  return (keysIo: WebAtKeysIo(memory, passphrase, codec: codec), prf: null);
}

/// The passkey unlock that opens [bytes], or null when no passkey yields one.
Future<({Uint8List credentialId, PrfSecret secret})?> _openWithPasskey(
    String atSign,
    Uint8List bytes,
    PasskeyKek kek,
    KeyEnvelopeCodec codec,
    Uint8List? hint) async {
  final ({Uint8List credentialId, PrfSecret secret}) unlocked;
  try {
    unlocked = await kek.unlock(atSign, credentialId: hint);
  } on PasskeyCeremonyException {
    return null;
  } on PrfUnavailableException {
    return null;
  }
  return await _opens(atSign, bytes, unlocked.secret, codec) ? unlocked : null;
}

/// Whether [bytes] opens with [secret]; false when it has no unlock of that
/// kind or none that opens.
Future<bool> _opens(String atSign, Uint8List bytes, UnlockSecret secret,
    KeyEnvelopeCodec codec) async {
  try {
    await codec.open(atSign, bytes, secret);
    return true;
  } on NoMatchingUnlockException {
    return false;
  } on EnvelopeUnlockFailedException {
    return false;
  }
}
