import 'dart:async';
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart' show Atsign;

/// An in-memory key store that, while [rerunning], runs each update's mutate
/// twice, as a store whose lock ran out before its put does: first on a copy
/// that is dropped, then, after [between], on a fresh read that is written.
class RerunningAtKeysIo extends InMemoryAtKeysIo {
  /// Whether each [update] runs its mutate twice.
  var rerunning = false;

  /// Runs between the two runs of each update, with the dropped copy as the
  /// first run left it, as another writer's turn would.
  Future<void> Function(AtKeys dropped)? between;

  /// How many updates ran their mutate twice.
  var reruns = 0;

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    if (rerunning) {
      final held = await read(atsign.toString());
      final copy = AtKeys.fromJson(
          jsonDecode(jsonEncode(held.toJson())) as Map<String, dynamic>);
      if (await mutate(copy) == false) return;
      reruns++;
      await between?.call(copy);
    }
    return super.update(atsign, mutate);
  }
}
