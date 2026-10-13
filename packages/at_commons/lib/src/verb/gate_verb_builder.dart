import 'package:at_commons/atsign.dart';
import 'package:at_commons/src/verb/verb_builder.dart';

/// The atSign's default, which decides every namespace no rule covers.
enum GateDefault { ungated, closed }

/// A setting of an open namespace's quarantine, named as the gate verb names
/// it. `window` is in seconds and `size` in bytes.
enum GateSetting { limit, window, size, maxQuarantined, maxQuarantinedBytes }

/// Builds a `gate:` command, which reads or changes an atServer's gate.
///
/// Each constructor takes exactly what its command needs, so no combination
/// the grammar refuses can be built. A namespace is lower-cased and must then
/// be dot-separated labels of word characters and hyphens, or the constructor
/// throws an [ArgumentError]. An atSign is made again with [Atsign], in case a
/// String was cast to one.
class GateVerbBuilder implements VerbBuilder {
  final String _command;

  /// Reads the atSign's default.
  GateVerbBuilder.readDefault() : _command = 'gate:default';

  /// Switches the atSign's default to [mode].
  GateVerbBuilder.switchDefault(GateDefault mode)
      : _command = 'gate:default:${mode.name}';

  /// Opens [namespace].
  GateVerbBuilder.open(String namespace)
      : _command = 'gate:rule:${_namespace(namespace)}:open';

  /// Opens [namespace] with [setting] set to [value], which must not be
  /// negative.
  GateVerbBuilder.openWith(String namespace, GateSetting setting, int value)
      : _command = 'gate:rule:${_namespace(namespace)}:open'
            ':${setting.name}:${_value(value)}';

  /// Opens [namespace] with [setting] returned to the operator's default.
  GateVerbBuilder.openWithDefault(String namespace, GateSetting setting)
      : _command =
            'gate:rule:${_namespace(namespace)}:open:${setting.name}:default';

  /// Closes [namespace], admitting [admit] in the same command when given.
  GateVerbBuilder.close(String namespace, {Atsign? admit})
      : _command = 'gate:rule:${_namespace(namespace)}:closed'
            '${admit == null ? '' : ':admit:${_atSign(admit)}'}';

  /// Removes [namespace]'s rule.
  GateVerbBuilder.removeRule(String namespace)
      : _command = 'gate:rule:${_namespace(namespace)}:none';

  /// Admits [atSign] in [namespace].
  GateVerbBuilder.admit(String namespace, Atsign atSign)
      : _command = 'gate:admit:${_namespace(namespace)}:${_atSign(atSign)}';

  /// Denies [atSign] in [namespace].
  GateVerbBuilder.deny(String namespace, Atsign atSign)
      : _command = 'gate:deny:${_namespace(namespace)}:${_atSign(atSign)}';

  /// Takes [atSign] out of [namespace]'s admitted or denied set.
  GateVerbBuilder.remove(String namespace, Atsign atSign)
      : _command = 'gate:remove:${_namespace(namespace)}:${_atSign(atSign)}';

  /// Admits [atSign] in the atSign-wide admitted set.
  GateVerbBuilder.admitAtSignWide(Atsign atSign)
      : _command = 'gate:admit:*:${_atSign(atSign)}';

  /// Takes [atSign] out of the atSign-wide admitted set.
  GateVerbBuilder.removeAtSignWide(Atsign atSign)
      : _command = 'gate:remove:*:${_atSign(atSign)}';

  /// Shows [namespace]'s rule and sets.
  GateVerbBuilder.show(String namespace)
      : _command = 'gate:show:${_namespace(namespace)}';

  /// Shows the atSign-wide admitted set.
  GateVerbBuilder.showAtSignWide() : _command = 'gate:show:*';

  /// Checks the standing [atSign] has in [namespace].
  GateVerbBuilder.check(String namespace, Atsign atSign)
      : _command = 'gate:check:${_namespace(namespace)}:${_atSign(atSign)}';

  /// Lists the namespaces with a rule or recorded admissions.
  GateVerbBuilder.list() : _command = 'gate:list';

  @override
  String buildCommand() => '$_command\n';

  @override
  bool checkParams() => true;
}

final RegExp _namespacePattern = RegExp(r'^[\w\-]+(?:\.[\w\-]+)*$');

String _namespace(String namespace) {
  final String lowered = namespace.toLowerCase();
  if (!_namespacePattern.hasMatch(lowered)) {
    throw ArgumentError.value(namespace, 'namespace',
        'must be dot-separated labels of word characters and hyphens');
  }
  return lowered;
}

String _atSign(Atsign atSign) => Atsign(atSign);

int _value(int value) {
  if (value < 0) {
    throw ArgumentError.value(value, 'value', 'must not be negative');
  }
  return value;
}
