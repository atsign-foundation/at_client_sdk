import 'dart:async';

import 'package:at_commons/at_commons.dart' show StoppedException;
import 'package:meta/meta.dart' show visibleForTesting;

/// What a write that finds no namespace key, or only one broader than start-up
/// will seed, waits on while its client's start-up has still to seed one:
/// which namespaces start-up seeds, once it knows, and when its seeding step
/// has finished.
///
/// A write never mints to find its own value's key. It only waits here, so
/// writes waiting together share the one seeding start-up does. A share whose
/// sender holds no key at the recipient's level, and a write to the atSign's
/// own key whose rotation policy asks for a new generation, still mint, under
/// the same mint lock as start-up.
class StartUpSeeding {
  /// The longest a write waits for start-up, in all.
  @visibleForTesting
  static Duration wait = const Duration(seconds: 30);

  final Completer<void> _namespaces = Completer<void>();
  Set<String> _seeded = const {};
  Completer<Set<String>?>? _recorded;
  final Completer<void> _finished = Completer<void>();
  final Completer<void> _stopped = Completer<void>();
  final Map<String, Object> _failures = {};

  /// Start-up seeds [namespaces], as soon as it knows them; a later report,
  /// such as the grants the seeding step reads, replaces an earlier one.
  void seeding(Set<String> namespaces) {
    _seeded = namespaces;
    if (!_namespaces.isCompleted) _namespaces.complete();
  }

  /// Start-up will say what it seeds from the grants its keyfile recorded,
  /// through [announced], before its seeding step reads them.
  void announcing() => _recorded ??= Completer<Set<String>?>();

  /// What start-up seeds under the grants its keyfile recorded, or null when
  /// the keyfile recorded none.
  void announced(Set<String>? namespaces) {
    if (namespaces != null) seeding(namespaces);
    final recorded = _recorded;
    if (recorded != null && !recorded.isCompleted) {
      recorded.complete(namespaces);
    }
  }

  /// Start-up could not seed [namespace], for [reason].
  void failed(String namespace, Object reason) =>
      _failures[namespace.toLowerCase()] = reason;

  /// Start-up's seeding step has ended, whatever it did.
  void finish() {
    if (!_namespaces.isCompleted) seeding(const {});
    if (!_finished.isCompleted) _finished.complete();
  }

  /// The client stopped, ending every wait.
  void stop() {
    if (!_stopped.isCompleted) _stopped.complete();
  }

  bool get isFinished => _finished.isCompleted;

  /// Why start-up could not seed [namespace], or null when it did not fail.
  Object? failureFor(String namespace) => _failures[namespace.toLowerCase()];

  /// The most specific namespace start-up seeds that [name], a key's whole
  /// name, ends with after a dot, once start-up's seeding step has finished.
  ///
  /// At once when the step has finished, and null as soon as start-up knows it
  /// seeds no namespace covering [name]. Throws [StoppedException] when the
  /// client stops first, and [TimeoutException], whose message is the
  /// namespace waited for when start-up knew it, when [wait] passes.
  Future<String?> covering(String name) async {
    if (isFinished) return _mostSpecific(_seeded, name);
    final deadline = DateTime.now().add(wait);
    await _until(_namespaces.future, deadline, null);
    final covering = _mostSpecific(_seeded, name);
    if (covering == null) return null;
    await _until(_finished.future, deadline, covering);
    return covering;
  }

  /// Like [covering], for a write that found a key at [found]: the namespace
  /// start-up seeds that covers [name] more specifically than [found], once
  /// the seeding step has finished.
  ///
  /// Null unless start-up has said what it seeds, or is about to from its
  /// keyfile, and that includes such a namespace. Throws as [covering] does.
  Future<String?> coveringBeyond(String name, String found) async {
    if (isFinished) return _beyond(name, found);
    final deadline = DateTime.now().add(wait);
    if (!_namespaces.isCompleted) {
      final recorded = _recorded;
      if (recorded == null ||
          await _until(recorded.future, deadline, null) == null) {
        return null;
      }
    }
    final narrower = _beyond(name, found);
    if (narrower == null) return null;
    await _until(_finished.future, deadline, narrower);
    return narrower;
  }

  /// The most specific namespace start-up seeds that covers [name] more
  /// specifically than [found], or null.
  String? _beyond(String name, String found) {
    final narrower = _mostSpecific(_seeded, name);
    return narrower != null && narrower.endsWith('.${found.toLowerCase()}')
        ? narrower
        : null;
  }

  /// The most specific of [namespaces] that [name] ends with after a dot,
  /// folded, or null.
  static String? _mostSpecific(Set<String> namespaces, String name) {
    final folded = name.toLowerCase();
    String? covering;
    for (final namespace in namespaces) {
      final candidate = namespace.toLowerCase();
      if (folded.endsWith('.$candidate') &&
          (covering == null || candidate.length > covering.length)) {
        covering = candidate;
      }
    }
    return covering;
  }

  Future<T> _until<T>(Future<T> future, DateTime deadline, String? namespace) {
    final left = deadline.difference(DateTime.now());
    return Future.any([
      future,
      _stopped.future.then<T>((_) => throw StoppedException(
          'the client stopped while a write waited for its start-up to '
          'publish a namespace key')),
    ]).timeout(left.isNegative ? Duration.zero : left,
        onTimeout: () => throw TimeoutException(namespace, wait));
  }
}
