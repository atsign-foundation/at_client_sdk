import 'dart:async';

import 'package:at_commons/at_commons.dart';

import 'at_lookup.dart';
import 'exception/at_lookup_exception.dart';

/// Where an atSign stands, as the atDirectory and its atServer report it.
enum AtSignServerState {
  /// The atDirectory has no entry for the atSign.
  notInDirectory,

  /// The atDirectory could not be asked.
  directoryUnreachable,

  /// The atDirectory knows the atSign, but its atServer did not answer.
  atServerUnreachable,

  /// The atServer answers and holds no public encryption key for the atSign.
  notActivated,

  /// The atServer holds the atSign's public encryption key.
  activated,
}

/// What [checkAtSignServer] found: the [state], and for the two unreachable
/// states the [cause] the lookup failed with.
final class AtSignServerCheck {
  final AtSignServerState state;
  final Object? cause;

  const AtSignServerCheck(this.state, [this.cause]);

  @override
  String toString() => cause == null ? state.name : '${state.name}: $cause';
}

/// Asks, over [lookUp], whether [atSign] is in the atDirectory, whether its
/// atServer answers, and whether the atSign has been activated.
///
/// The address comes from [lookUp]'s own finder and the question travels over
/// [lookUp]'s own transport, so the answer is about the route the caller's
/// connections take. Nothing is authenticated. [timeout] bounds each of the two
/// network steps.
Future<AtSignServerCheck> checkAtSignServer(AtLookUp lookUp, String atSign,
    {Duration? timeout}) async {
  final normalized = atSign.startsWith('@') ? atSign : '@$atSign';
  try {
    await lookUp.secondaryAddressFinder
        .findSecondary(normalized, timeout: timeout);
  } on SecondaryNotFoundException catch (e) {
    return AtSignServerCheck(AtSignServerState.notInDirectory, e);
  } catch (e) {
    return AtSignServerCheck(AtSignServerState.directoryUnreachable, e);
  }

  final String? response;
  try {
    final lookup =
        lookUp.executeCommand('lookup:publickey$normalized\n', auth: false);
    response = await (timeout == null ? lookup : lookup.timeout(timeout));
  } on AtLookUpException catch (e) {
    if (e.errorCode == 'AT0015') {
      return AtSignServerCheck(AtSignServerState.notActivated);
    }
    return AtSignServerCheck(AtSignServerState.atServerUnreachable, e);
  } catch (e) {
    return AtSignServerCheck(AtSignServerState.atServerUnreachable, e);
  }

  final value = response?.replaceFirst(RegExp(r'^data:'), '').trim();
  if (value == null || value.isEmpty || value == 'null') {
    return AtSignServerCheck(AtSignServerState.notActivated);
  }
  return AtSignServerCheck(AtSignServerState.activated);
}
