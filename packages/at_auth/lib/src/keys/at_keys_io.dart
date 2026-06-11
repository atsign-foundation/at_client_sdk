import 'dart:async';

import 'package:at_auth/src/keys/at_keys_codec.dart';
import 'package:at_auth/src/keys/at_keys_passphrase_envelope.dart';
import 'package:at_auth/src/keys/at_keys_resolver.dart';
import 'package:at_auth/src/keys/legacy/legacy_at_keys_adapter.dart';
import 'package:at_commons/at_commons.dart';

class AtKeysReadOptions {
  final String? passPhrase;
  final bool allowLegacy;
  final bool unlockProtectedKeys;

  const AtKeysReadOptions({
    this.passPhrase,
    this.allowLegacy = true,
    this.unlockProtectedKeys = false,
  });
}

class AtKeysWriteOptions {
  final String? passPhrase;
  final bool overwrite;
  final bool protectPrivateKeys;

  const AtKeysWriteOptions({
    this.passPhrase,
    this.overwrite = false,
    this.protectPrivateKeys = false,
  });
}

class AtKeysGenerateOptions {
  final String? publicKeyId;

  const AtKeysGenerateOptions({
    this.publicKeyId,
  });
}

/// Interaction layer for reading resolved atKeys from storage.
///
/// Concrete implementations own storage-specific I/O and use the standard
/// codec/resolver pipeline exposed here.
sealed class AtKeysIo {
  final AtKeysCodec codec;
  final AtKeysResolver resolver;
  final AtKeysPassphraseEnvelopeCodec passphraseEnvelopeCodec;
  final LegacyAtKeysAdapter legacyAtKeysAdapter;

  AtKeysIo({
    AtKeysCodec? codec,
    AtKeysResolver? resolver,
    AtKeysPassphraseEnvelopeCodec? passphraseEnvelopeCodec,
    LegacyAtKeysAdapter? legacyAtKeysAdapter,
  })  : codec = codec ?? AtKeysJsonCodec(),
        resolver = resolver ?? AtKeysDocumentResolver(),
        passphraseEnvelopeCodec =
            passphraseEnvelopeCodec ?? AtKeysPassphraseEnvelopeCodec(),
        legacyAtKeysAdapter = legacyAtKeysAdapter ?? LegacyAtKeysAdapter();

  FutureOr<AtKeysSet> read(
    String atsign, {
    AtKeysReadOptions? options,
  });
}

abstract class WrittenAtKeysIo extends AtKeysIo {
  WrittenAtKeysIo({
    super.codec,
    super.resolver,
    super.passphraseEnvelopeCodec,
    super.legacyAtKeysAdapter,
  });

  Future<void> write(
    String atsign,
    AtKeysSet keys, {
    AtKeysWriteOptions? options,
  });

  Future<void> update(String atsign, AtKeysSet keys);
}

abstract class GeneratedAtKeysIo extends AtKeysIo {
  GeneratedAtKeysIo({
    super.codec,
    super.resolver,
    super.passphraseEnvelopeCodec,
    super.legacyAtKeysAdapter,
  });

  FutureOr<AtKeysSet> generateKeys(
    String atSign, {
    AtKeysGenerateOptions? options,
  });
}
