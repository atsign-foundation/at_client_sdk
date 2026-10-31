import 'dart:io';

import 'package:path/path.dart' as p;

/// The largest source file the generator parses.
const int maxSourceBytes = 2 * 1024 * 1024;

/// A file the generator refused to read.
class SourceError implements Exception {
  /// Creates the error for [path].
  SourceError(this.path, this.message);

  /// The file, relative to its root.
  final String path;

  /// Why it was refused.
  final String message;

  @override
  String toString() => '$path: $message';
}

/// Runs git in [dir] and returns its stdout, or null when git fails.
String? git(String dir, List<String> args) {
  final r = Process.runSync('git', ['-C', dir, ...args],
      stdoutEncoding: const SystemEncoding(), runInShell: false);
  if (r.exitCode != 0) return null;
  return r.stdout as String;
}

/// Files read from one root: a checkout's working tree, with in-memory
/// overlays taking precedence.
class Tree {
  /// Creates a tree over [dir], named [name] ("sdk" or "server").
  Tree(this.name, String dir,
      {Map<String, String>? overlays, this.tracked = false})
      : dir = p.normalize(p.absolute(dir)),
        overlays = overlays ?? {};

  /// Whether only files git tracks are listed, leaving untracked ones out.
  final bool tracked;

  /// The root's name in the model.
  final String name;

  /// The checkout's absolute path.
  final String dir;

  /// Contents that replace or add files, by path relative to [dir].
  final Map<String, String> overlays;

  /// The absolute path of [path].
  String absolute(String path) => p.join(dir, path);

  /// The contents of [path], or null when it does not exist.
  ///
  /// Throws [SourceError] for a file over [maxSourceBytes].
  String? read(String path) {
    final o = overlays[path];
    final text = o ?? _readDisk(path);
    if (text != null && text.length > maxSourceBytes) {
      throw SourceError(
          path,
          'is ${text.length} bytes, over the cap of '
          '$maxSourceBytes');
    }
    return text;
  }

  String? _readDisk(String path) {
    if (!isSafeRelative(path)) return null;
    final f = File(absolute(path));
    if (!f.existsSync()) return null;
    if (f.lengthSync() > maxSourceBytes) {
      throw SourceError(
          path,
          'is ${f.lengthSync()} bytes, over the cap of '
          '$maxSourceBytes');
    }
    return f.readAsStringSync();
  }

  List<String>? _listed;

  /// Every file git would track here, plus overlays, sorted.
  List<String> files() {
    _listed ??= (git(dir, [
              'ls-files',
              '--cached',
              if (!tracked) ...['--others', '--exclude-standard']
            ]) ??
            '')
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList();
    return ({..._listed!, ...overlays.keys}.toList()..sort());
  }

  /// The files under [prefix] ending in [suffix].
  List<String> filesUnder(String prefix, {String suffix = ''}) =>
      files().where((f) => f.startsWith(prefix) && f.endsWith(suffix)).toList();
}

/// Files read from a git commit, for comparing against a ref no checkout
/// holds.
class GitRefTree {
  /// Creates a tree over [sha] in the repository at [repo].
  GitRefTree(this.repo, this.sha);

  /// The repository.
  final String repo;

  /// The commit.
  final String sha;

  final Map<String, String?> _cache = {};

  /// The contents of [path] at [sha], or null when it does not exist there.
  String? read(String path) => _cache.putIfAbsent(path, () {
        if (!isSafeRelative(path)) return null;
        return git(repo, ['show', '$sha:$path']);
      });
}

/// Whether [path] is relative and stays inside its root.
bool isSafeRelative(String path) {
  if (path.isEmpty || p.isAbsolute(path) || path.contains('\\')) return false;
  return !p.split(path).any((s) => s == '..' || s == '.');
}
