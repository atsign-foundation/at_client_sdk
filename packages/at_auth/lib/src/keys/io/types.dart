import 'dart:async';

import 'package:at_auth/src/keys/atkeys.dart';
import 'package:at_auth/src/keys/serialization/codec.dart';
import 'package:at_auth/src/keys/serialization/resolver.dart';
import 'package:at_commons/at_commons.dart';
import 'package:meta/meta.dart';
//todo: remove legacy imports when v4
import 'package:at_auth/src/keys/legacy/at_keys_legacy.dart';
import 'package:at_auth/src/keys/legacy/legacy_atkeysio.dart';

/// An interface that defines methods for reading AtKeys.
/// It can be implemented by classes that read AtKeys from different sources,
sealed class AtKeysIo {
  final AtKeysCodec codec;
  final AtKeysResolver resolver;

  // for mocking
  @visibleForTesting
  const AtKeysIo({
    AtKeysCodec? codec,
    AtKeysResolver? resolver,
  })  : codec = codec ?? const AtKeysJsonCodec(),
        resolver = resolver ?? const AtKeysDocumentResolver();
  FutureOr<AtKeysSet> read(Atsign atsign);
}

/// An interface that defines methods for the AtKeysSet that are written.
/// Implemented by any classes that write an AtKeysSet to different sources.
/// such as file system or keychain.
abstract class WritableAtKeysIo extends AtKeysIo {
  const WritableAtKeysIo({
    super.codec,
    super.resolver,
  });

  FutureOr<void> write(WritableAtKeysSet atKeys);
  FutureOr<void> append({
    required AtKeysMaterial key,
    required WritableAtKeysSet source,
  });
  FutureOr<void> remove(Atsign atsign);
  FutureOr<void> update(WritableAtKeysSet atKeys);
}

/// An interface that defines methods for AtKeys that can be generated.
/// It can be implemented by classes that generate AtKeys using different methods,
/// such as secure element.
abstract class GeneratedAtKeysIo extends AtKeysIo {
  const GeneratedAtKeysIo({
    super.codec,
    super.resolver,
  });
  FutureOr<void> generateKeys(String clientId);
  FutureOr<void> dispose(String clientId);
}

/// An interface that defines methods for AtKeys that can be written.
/// It can be implemented by classes that write AtKeys to different sources,
/// such as file system or keychain.
@Deprecated('Deprecated, please use WritableAtKeysIo') //todo: remove v4
abstract class WrittenAtKeysIo extends AtKeysIo {
  @override
  Future<AtKeysSet> read(Atsign atsign);
  Future write(Atsign atsign, AtKeys atKeys);

  FutureOr<AtKeys> decryptAtKeysWithSelfEncKey(
      Map<String, dynamic> jsonData, PkamAuthMode authMode) async {
    return FileAtKeysIoStatic.decryptAtKeysWithSelfEncKey(jsonData, authMode);
  }
}
