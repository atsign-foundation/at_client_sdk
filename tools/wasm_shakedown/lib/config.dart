/// Reads `.github/wasm_gates.yaml`: which packages are gated, and what each
/// gate promises.
///
/// Parsing is strict because there is no Dart call site for an IDE to check — a
/// typo has to fail loudly here rather than quietly narrowing a gate. Unknown
/// keys, missing fields, unresolvable barrels and barrels belonging to another
/// package are all errors naming the line.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

import 'wasm_shakedown.dart';

/// Where the registry lives, relative to the workspace root. Under `.github/`
/// beside `dependabot.yaml`: repo policy, not something a package ships.
const gateConfigPath = '.github/wasm_gates.yaml';

/// A config that could not be read. Names the file and, usually, the line.
class GateConfigException implements Exception {
  final String message;
  GateConfigException(this.message);
  @override
  String toString() => message;
}

/// One `ratchets:` entry: a barrel and the one-way baseline it is held to.
class RatchetSpec {
  final String barrel;

  /// Package-relative paths permitted to reach a forbidden library.
  final Set<String> allowedOffenders;

  /// A ceiling on how many packages anywhere in the graph own an offender.
  final int maxBlockedPackages;

  /// The floor under the walk's file count. Set near the real figure, not to 1.
  final int minFilesWalked;

  const RatchetSpec({
    required this.barrel,
    required this.allowedOffenders,
    required this.maxBlockedPackages,
    required this.minFilesWalked,
  });
}

/// One `controls:` entry: a barrel that must still *reach* something, so a walk
/// that found nothing cannot read as a pass. See [ControlVerdict].
class ControlSpec {
  final String barrel;
  final String? reachesFile;
  final String? reachesLibrary;

  /// What this control keeps reachable, in prose, for the failure message.
  final String because;

  /// Whose view of configurable URIs to resolve with. Defaults to io, since a
  /// control walks the platform side of a seam; `web` pins the other branch.
  final Map<String, bool> environment;

  const ControlSpec({
    required this.barrel,
    required this.because,
    required this.environment,
    this.reachesFile,
    this.reachesLibrary,
  });
}

/// One package's gate: its ratchets, the barrels its compile probe imports, and
/// its controls.
class PackageGate {
  final String package;
  final List<RatchetSpec> ratchets;

  /// The barrels a generated probe imports.
  final List<String> probe;

  final List<ControlSpec> controls;

  const PackageGate({
    required this.package,
    required this.ratchets,
    required this.probe,
    required this.controls,
  });
}

/// Every gated package, in the order the config lists them.
class GateConfig {
  final List<PackageGate> gates;

  /// Where this was read from, for messages.
  final String path;

  const GateConfig(this.gates, this.path);

  /// The gate for [package], or null.
  PackageGate? operator [](String package) =>
      gates.where((g) => g.package == package).firstOrNull;

  /// Reads and validates a gate config.
  ///
  /// [path] is taken as given, relative to the current directory or absolute.
  /// Without it the default is `<root>/$gateConfigPath`, [root] defaulting to the
  /// pub workspace root so it resolves the same file from anywhere in the repo.
  ///
  /// Package names are always checked against the workspace's own package
  /// config, whatever [path] says: a config elsewhere still describes these
  /// packages.
  static GateConfig load({Directory? root, Directory? from, String? path}) {
    final base = root ?? workspaceRoot(from: from);
    final file = File(path ?? '${base.path}/$gateConfigPath');
    if (!file.existsSync()) {
      // The absolute path, because a relative --config resolves against the
      // current directory while the default resolves against the workspace
      // root — so the two disagree, and the message has to say which it tried.
      throw GateConfigException('no gate config at ${file.absolute.path} — '
          'this is the registry of gated packages, and without it there is '
          'nothing to check');
    }
    return parse(file.readAsStringSync(),
        path: file.path, knownPackages: resolvePackageRoots(from: base).keys);
  }

  /// Parses [source], rejecting anything it cannot account for. A stanza name
  /// outside [knownPackages] resolves to no root, so its checks would pass by
  /// speaking for a package that does not exist.
  static GateConfig parse(
    String source, {
    required String path,
    required Iterable<String> knownPackages,
  }) {
    final doc = loadYamlNode(source);
    if (doc is! YamlMap) {
      throw GateConfigException('$path: expected a map of package name to '
          'gate, got ${doc.runtimeType}');
    }

    final known = knownPackages.toSet();
    final gates = <PackageGate>[];
    for (final entry in doc.nodes.entries) {
      final name = (entry.key as YamlScalar).value;
      if (name is! String) {
        throw GateConfigException(_at(
            path, entry.key as YamlNode, 'a package name must be a string'));
      }
      if (!known.contains(name)) {
        throw GateConfigException(_at(
            path,
            entry.key as YamlNode,
            '"$name" is not a package in this workspace. Every check in this '
            'stanza is scoped to that name, so a name the package config '
            'does not know would read as a clean result'));
      }
      gates.add(_gate(path, name, entry.value));
    }
    return GateConfig(gates, path);
  }

  static PackageGate _gate(String path, String name, YamlNode node) {
    final map = _expectMap(path, node, 'the gate for $name');
    _rejectUnknown(path, map, const {'ratchets', 'probe', 'controls'}, name);

    final ratchets = _expectList(path, map, 'ratchets', name)
        .map((n) => _ratchet(path, n, name))
        .toList();
    if (ratchets.isEmpty) {
      throw GateConfigException(_at(path, map,
          '$name lists no ratchets, so its gate would check nothing'));
    }

    final probe = _expectList(path, map, 'probe', name).map((n) {
      final uri = _scalar<String>(path, n, 'a probe barrel');
      return _barrel(path, n, uri, name);
    }).toList();
    if (probe.isEmpty) {
      throw GateConfigException(_at(
          path,
          map,
          '$name lists no probe barrels. A probe that imports nothing compiles '
          'clean forever, which is a green that says nothing'));
    }

    final controls = _expectList(path, map, 'controls', name)
        .map((n) => _control(path, n, name))
        .toList();
    if (controls.isEmpty) {
      throw GateConfigException(_at(
          path,
          map,
          '$name lists no controls. Every ratchet check is about what the '
          'walk did not find, and a walk that found nothing satisfies all '
          'of them, so without a positive control this gate cannot tell a '
          'clean package from a stalled walk'));
    }

    return PackageGate(
        package: name, ratchets: ratchets, probe: probe, controls: controls);
  }

  static RatchetSpec _ratchet(String path, YamlNode node, String name) {
    final map = _expectMap(path, node, 'a ratchet for $name');
    _rejectUnknown(
        path,
        map,
        const {
          'barrel',
          'allowed_offenders',
          'max_blocked_packages',
          'min_files_walked',
        },
        name);

    final barrelNode = _required(path, map, 'barrel', name);
    return RatchetSpec(
      barrel: _barrel(
          path, barrelNode, _scalar<String>(path, barrelNode, 'barrel'), name),
      allowedOffenders: {
        for (final n in map.nodes['allowed_offenders'] == null
            ? const <YamlNode>[]
            : _expectList(path, map, 'allowed_offenders', name))
          _scalar<String>(path, n, 'an allowed offender'),
      },
      maxBlockedPackages: _scalar<int>(
          path,
          _required(path, map, 'max_blocked_packages', name),
          'a package count'),
      minFilesWalked: _scalar<int>(
          path, _required(path, map, 'min_files_walked', name), 'a file count'),
    );
  }

  static ControlSpec _control(String path, YamlNode node, String name) {
    final map = _expectMap(path, node, 'a control for $name');
    _rejectUnknown(
        path,
        map,
        const {
          'barrel',
          'reaches_file',
          'reaches_library',
          'because',
          'environment',
        },
        name);

    final barrelNode = _required(path, map, 'barrel', name);
    final file = map.nodes['reaches_file'];
    final library = map.nodes['reaches_library'];
    if (file == null && library == null) {
      throw GateConfigException(_at(
          path,
          map,
          'this control names neither reaches_file nor reaches_library. A '
          'control asserting nothing passes on a walk that found nothing, '
          'which is the failure it exists to catch'));
    }

    final env = map.nodes['environment'];
    final envName =
        env == null ? 'io' : _scalar<String>(path, env, 'io or web');
    if (envName != 'io' && envName != 'web') {
      throw GateConfigException(
          _at(path, env!, 'environment must be "io" or "web", got "$envName"'));
    }

    return ControlSpec(
      barrel: _barrel(
          path, barrelNode, _scalar<String>(path, barrelNode, 'barrel'), name),
      reachesFile:
          file == null ? null : _scalar<String>(path, file, 'reaches_file'),
      reachesLibrary: library == null
          ? null
          : _scalar<String>(path, library, 'reaches_library'),
      because: _scalar<String>(
          path, _required(path, map, 'because', name), 'because'),
      environment: envName == 'io' ? ioEnvironment : webEnvironment,
    );
  }

  /// Every barrel in [gates] that does not resolve on disk, as
  /// `barrel -> reason` — a renamed barrel would otherwise make a gate walk
  /// less and still pass. Separate from parsing, which needs no package roots.
  Map<String, String> unresolvableBarrels(Map<String, String> roots) {
    final bad = <String, String>{};
    for (final gate in gates) {
      final barrels = [
        for (final r in gate.ratchets) r.barrel,
        ...gate.probe,
        for (final c in gate.controls) c.barrel,
      ];
      for (final barrel in barrels) {
        final rest = barrel.substring('package:'.length);
        final slash = rest.indexOf('/');
        final root = roots[rest.substring(0, slash)];
        if (root == null) {
          bad[barrel] = 'no such package in this workspace';
        } else if (!File('$root${rest.substring(slash + 1)}').existsSync()) {
          bad[barrel] = 'no such file: $root${rest.substring(slash + 1)}';
        }
      }
    }
    return bad;
  }

  static String _barrel(
      String path, YamlNode node, String uri, String package) {
    if (!uri.startsWith('package:') || !uri.contains('/')) {
      throw GateConfigException(
          _at(path, node, 'a barrel must be a package: URI, got "$uri"'));
    }
    final authority = uri.substring('package:'.length, uri.indexOf('/'));
    if (authority != package) {
      throw GateConfigException(_at(
          path,
          node,
          'barrel "$uri" belongs to $authority, not $package. Offenders are '
          'filtered by the stanza name, so a barrel from another package '
          'walks a graph this gate never examines and reports a clean '
          'result'));
    }
    return uri;
  }

  static YamlNode _required(String path, YamlMap map, String key, String name) {
    final node = map.nodes[key];
    if (node == null) {
      throw GateConfigException(_at(path, map, '$name is missing "$key"'));
    }
    return node;
  }

  static YamlMap _expectMap(String path, YamlNode node, String what) =>
      node is YamlMap
          ? node
          : throw GateConfigException(_at(path, node, '$what must be a map'));

  static Iterable<YamlNode> _expectList(
      String path, YamlMap map, String key, String name) {
    final node = _required(path, map, key, name);
    if (node is! YamlList) {
      throw GateConfigException(_at(path, node, '"$key" must be a list'));
    }
    return node.nodes;
  }

  static T _scalar<T>(String path, YamlNode node, String what) {
    final value = node is YamlScalar ? node.value : null;
    return value is T
        ? value
        : throw GateConfigException(
            _at(path, node, '$what must be $T, got "${node.value}"'));
  }

  static void _rejectUnknown(
      String path, YamlMap map, Set<String> allowed, String name) {
    for (final key in map.nodes.keys) {
      final k = (key as YamlNode).value;
      if (!allowed.contains(k)) {
        throw GateConfigException(_at(
            path,
            key,
            'unknown key "$k" in $name. Allowed here: '
            '${(allowed.toList()..sort()).join(', ')}'));
      }
    }
  }

  /// Prefixed with the file and the 1-based line of [node].
  static String _at(String path, YamlNode node, String message) =>
      '$path:${node.span.start.line + 1}: $message';
}
