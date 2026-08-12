import 'package:at_auth/src/at_auth.dart' show AtServerProbe;
import 'package:at_auth/src/io/probe.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_auth/src/keys/io/file_io.dart';

/// The `dart:io` defaults `AtAuthImpl` picks up when `dart.library.io` is
/// available — i.e. everywhere except a web/WASM build.
///
/// `defaults_stub.dart` is the other half of the pair and returns null for both,
/// which is what makes `at_auth_web.dart` free of `dart:io` without changing
/// behaviour for anyone on native.

/// A fresh [FileAtKeysIo] at the default `~/.atsign/keys/` location.
///
/// A new instance per call, matching the `atKeysIo ??= FileAtKeysIo()` this
/// replaced: [FileAtKeysIo] carries a `filePath` closure and a passphrase, so a
/// shared instance would leak configuration between onboards.
AtKeysIo? defaultAtKeysIo() => FileAtKeysIo();

/// The TLS atServer readiness probe.
AtServerProbe? defaultProbeSocket() => secureSocketProbe;
