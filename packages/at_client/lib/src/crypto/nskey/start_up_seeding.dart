import 'dart:async';

import 'package:at_commons/at_commons.dart' show StoppedException;
import 'package:meta/meta.dart' show visibleForTesting;

/// What a write that finds no namespace key waits on while its client's
/// start-up has still to seed one: which namespaces start-up seeds, once it
/// knows, and when its seeding step has finished.
///
/// A write never mints. It only waits here, so writes waiting together share
/// the one seeding start-up does.
class StartUpSeeding {
  /// The longest a write waits for start-up, in all.
  @visibleForTesting
  static Duration wait = const Duration(seconds: 30);

  final Completer<Set<String>> _namespaces = Completer<Set<String>>();
  final Completer<void> _finished = Completer<void>();
  final Completer<void> _stopped = Completer<void>();
  final Map<String, Object> _failures = {};

  /// Start-up seeds [namespaces]; reported once, as soon as it knows them.
  void seeding(Set<String> namespaces) {
    if (!_namespaces.isCompleted) _namespaces.complete(namespaces);
  }

  /// Start-up could not seed [namespace], for [reason].
  void failed(String namespace, Object reason) =>
      _failures[namespace.toLowerCase()] = reason;

  /// Start-up's seeding step has ended, whatever it did.
  void finish() {
    seeding(const {});
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
  /// Null at once when the step has finished, and null as soon as start-up
  /// knows it seeds no namespace covering [name]. Throws [StoppedException]
  /// when the client stops first, and [TimeoutException], whose message is the
  /// namespace waited for when start-up knew it, when [wait] passes.
  Future<String?> covering(String name) async {
    if (isFinished) return null;
    final deadline = DateTime.now().add(wait);
    final covering =
        _mostSpecific(await _until(_namespaces.future, deadline, null), name);
    if (covering == null) return null;
    await _until(_finished.future, deadline, covering);
    return covering;
  }

  /// Like [covering], for a write that found a key at [found]: the namespace
  /// start-up seeds that covers [name] more specifically than [found], once
  /// the seeding step has finished.
  ///
  /// Null at once unless start-up has already said what it seeds and that
  /// includes such a namespace. Throws as [covering] does.
  Future<String?> coveringBeyond(String name, String found) async {
    if (isFinished || !_namespaces.isCompleted) return null;
    final narrower = _mostSpecific(await _namespaces.future, name);
    if (narrower == null || !narrower.endsWith('.${found.toLowerCase()}')) {
      return null;
    }
    await _until(_finished.future, DateTime.now().add(wait), narrower);
    return narrower;
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
