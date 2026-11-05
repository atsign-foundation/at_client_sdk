import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;

import 'decls.dart';

/// Resolved analysis of the two roots, sharing one overlay so a test can
/// change a file in memory.
class Resolver {
  /// Creates a resolver over the SDK checkout [sdkDir] and the at_server
  /// checkout [serverDir], resolving [sdkPackages] and [serverPackage].
  Resolver(
      {required this.sdkDir,
      required this.serverDir,
      required this.sdkPackages,
      required this.serverPackage});

  /// The SDK checkout.
  final String sdkDir;

  /// The at_server checkout.
  final String serverDir;

  /// SDK packages to resolve, relative to [sdkDir].
  final List<String> sdkPackages;

  /// The at_server package to resolve, relative to [serverDir].
  final String serverPackage;

  /// The file system every analysis reads.
  final OverlayResourceProvider provider =
      OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);

  AnalysisContextCollection? _sdk;
  AnalysisContextCollection? _server;
  final Map<String, String> _overlays = {};
  int _stamp = 0;

  AnalysisContextCollection get _sdkCollection =>
      _sdk ??= AnalysisContextCollection(
          includedPaths: [for (final s in sdkPackages) p.join(sdkDir, s)],
          resourceProvider: provider);

  AnalysisContextCollection get _serverCollection =>
      _server ??= AnalysisContextCollection(
          includedPaths: [p.join(serverDir, serverPackage)],
          resourceProvider: provider);

  Iterable<AnalysisContext> get _contexts => [
        if (_sdk != null) ..._sdk!.contexts,
        if (_server != null) ..._server!.contexts,
      ];

  /// Replaces the overlays with [overlays], absolute path to contents.
  Future<void> setOverlays(Map<String, String> overlays) async {
    final changed = <String>{};
    for (final path in _overlays.keys.toList()) {
      if (!overlays.containsKey(path)) {
        provider.removeOverlay(path);
        _overlays.remove(path);
        changed.add(path);
      }
    }
    for (final e in overlays.entries) {
      if (_overlays[e.key] == e.value) continue;
      provider.setOverlay(e.key, content: e.value, modificationStamp: ++_stamp);
      _overlays[e.key] = e.value;
      changed.add(e.key);
    }
    if (changed.isEmpty) return;
    for (final c in _contexts) {
      for (final path in changed) {
        c.changeFile(path);
      }
      await c.applyPendingFileChanges();
    }
  }

  AnalysisContext _contextFor(String path) {
    if (p.isWithin(serverDir, path)) {
      return _serverCollection.contextFor(path);
    }
    return _sdkCollection.contextFor(path);
  }

  /// The resolved unit of [path], or null when it does not resolve.
  Future<ResolvedUnitResult?> unit(String path) async {
    final r = await _contextFor(path).currentSession.getResolvedUnit(path);
    return r is ResolvedUnitResult ? r : null;
  }

  /// The resolved declaration of the qualified [symbol] in [path].
  Future<AstNode?> declaration(String path, String symbol) async {
    final u = await unit(path);
    if (u == null) return null;
    final hits = indexDeclarations(u.unit)[symbol];
    return hits == null || hits.length != 1 ? null : hits.single.node;
  }

  /// The resolved declaration of [element], when its source is in one of
  /// the two checkouts.
  Future<AstNode?> declarationOf(Element element) async {
    final path = sourcePath(element);
    final library = element.library;
    final session = element.session;
    if (path == null ||
        !isInRoots(path) ||
        library == null ||
        session == null) {
      return null;
    }
    final r = await session.getResolvedLibraryByElement(library);
    if (r is! ResolvedLibraryResult) return null;
    AstNode? found;
    for (final u in r.units) {
      if (u.path != path) continue;
      u.unit.accept(_FindDeclared(element.baseElement, (n) => found ??= n));
    }
    return found;
  }

  /// Whether [path] is inside either checkout.
  bool isInRoots(String path) =>
      p.isWithin(serverDir, path) || p.isWithin(sdkDir, path);

  /// The library [uri] resolves to in the at_server package's context.
  Future<LibraryElement?> serverLibrary(String uri) async {
    final ctx =
        _serverCollection.contextFor(p.join(serverDir, serverPackage, 'lib'));
    final r = await ctx.currentSession.getLibraryByUri(uri);
    return r is LibraryElementResult ? r.element : null;
  }

  /// The library [uri] resolves to in the SDK's context.
  Future<LibraryElement?> sdkLibrary(String uri) async {
    final ctx = _sdkCollection.contextFor(p.join(sdkDir, sdkPackages.first));
    final r = await ctx.currentSession.getLibraryByUri(uri);
    return r is LibraryElementResult ? r.element : null;
  }

  /// The file [uri] maps to in the at_server package's context.
  String? serverPathOf(String uri) {
    final ctx =
        _serverCollection.contextFor(p.join(serverDir, serverPackage, 'lib'));
    return ctx.currentSession.uriConverter.uriToPath(Uri.parse(uri));
  }
}

/// The file [element] is declared in.
String? sourcePath(Element element) =>
    element.firstFragment.libraryFragment?.source.fullName;

/// `Class.member` or a top-level name for [element].
String qualifiedName(Element element) {
  final e = element.baseElement;
  final enclosing = e.enclosingElement;
  final name = e is ConstructorElement
      ? (e.name == null || e.name == '' ? 'new' : e.name!)
      : (e is PropertyAccessorElement ? e.variable.name : e.name) ?? '?';
  if (enclosing is InterfaceElement ||
      enclosing is ExtensionElement ||
      enclosing is MixinElement) {
    return '${enclosing!.name}.$name';
  }
  return name;
}

class _FindDeclared extends RecursiveAstVisitor<void> {
  _FindDeclared(this.element, this.found);
  final Element element;
  final void Function(AstNode) found;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.declaredFragment?.element.baseElement == element) found(node);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.declaredFragment?.element.baseElement == element) found(node);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.declaredFragment?.element.baseElement == element) found(node);
    super.visitConstructorDeclaration(node);
  }
}
