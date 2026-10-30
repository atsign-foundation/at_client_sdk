import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:test/test.dart';

/// Catalogue: features/at_client/at_chops_4.feature
void main() {
  const banned = {'AtChops', 'AtChopsImpl', 'AtChopsKeys'};

  /// Each spelling of the three, as a type or as a member holding one.
  final token = RegExp(r'(?<![A-Za-z0-9_$])'
      r'(?:_?atChops(?:Keys)?|AtChops(?:Impl|Keys)?)'
      r'(?![A-Za-z0-9_$])');

  late AnalysisContextCollection collection;

  setUpAll(() => collection = AnalysisContextCollection(
      includedPaths: [Directory.current.absolute.path]));

  Future<LibraryElement> libraryAt(String uri) async {
    final result = await collection
        .contextFor(Directory.current.absolute.path)
        .currentSession
        .getLibraryByUri(uri);
    if (result is! LibraryElementResult) fail('$uri did not resolve: $result');
    return result.element;
  }

  bool isBanned(Element element) =>
      banned.contains(element.name) &&
      element.library!.uri.toString().startsWith('package:at_chops/');

  /// The banned types [type] names anywhere in it.
  Set<String> bannedIn(DartType? type, [Set<DartType>? seen]) {
    seen ??= {};
    if (type == null || !seen.add(type)) return {};
    final found = <String>{
      if (type.alias case final alias?)
        for (final argument in alias.typeArguments) ...bannedIn(argument, seen),
    };
    switch (type) {
      case InterfaceType():
        if (isBanned(type.element)) found.add(type.element.name!);
        for (final argument in type.typeArguments) {
          found.addAll(bannedIn(argument, seen));
        }
      case FunctionType():
        found.addAll(bannedIn(type.returnType, seen));
        for (final parameter in type.formalParameters) {
          found.addAll(bannedIn(parameter.type, seen));
        }
        for (final parameter in type.typeParameters) {
          found.addAll(bannedIn(parameter.bound, seen));
        }
      case RecordType():
        for (final field in type.positionalFields) {
          found.addAll(bannedIn(field.type, seen));
        }
        for (final field in type.namedFields) {
          found.addAll(bannedIn(field.type, seen));
        }
      case TypeParameterType():
        found.addAll(bannedIn(type.bound, seen));
    }
    return found;
  }

  /// Every public way [element] takes, returns or exposes a banned type, as
  /// `where: Type`, inherited members included.
  List<String> exposures(Element element) {
    final name = element.name;
    final found = <String>[];
    void check(String where, DartType? type) {
      final named = bannedIn(type);
      if (named.isNotEmpty) found.add('$where: ${named.join(', ')}');
    }

    if (isBanned(element)) found.add('$name itself');
    switch (element) {
      case InstanceElement():
        final owners = <InstanceElement>[
          element,
          if (element is InterfaceElement)
            for (final supertype in element.allSupertypes) supertype.element,
        ];
        if (element is InterfaceElement) {
          for (final supertype in element.allSupertypes) {
            check('$name supertype', supertype);
          }
        }
        if (element is ExtensionElement) {
          check('$name on', element.extendedType);
        }
        for (final owner in owners) {
          final members = <Element>[
            ...owner.fields,
            ...owner.methods,
            ...owner.getters,
            ...owner.setters,
            if (owner == element && owner is InterfaceElement)
              ...owner.constructors,
          ];
          for (final member in members.where((m) => !m.isPrivate)) {
            check(
                '$name.${member.name}',
                member is VariableElement
                    ? member.type
                    : (member as ExecutableElement).type);
          }
        }
      case ExecutableElement():
        check('$name', element.type);
      case VariableElement():
        check('$name', element.type);
      case TypeAliasElement():
        check('$name', element.aliasedType);
    }
    return found;
  }

  test('The public API names no AtChops', () async {
    final barrels = [
      for (final package in ['at_client', 'at_auth'])
        for (final file in Directory('../$package/lib')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
          'package:$package/${file.uri.pathSegments.last}'
    ];
    expect(
        barrels,
        containsAll([
          'package:at_client/at_client.dart',
          'package:at_auth/at_auth.dart'
        ]));

    var exported = 0;
    final found = <String>[];
    for (final uri in barrels) {
      final library = await libraryAt(uri);
      for (final element in library.exportNamespace.definedNames2.values) {
        exported++;
        found.addAll(exposures(element).map((e) => '$uri $e'));
      }
    }
    print('read $exported exported names from ${barrels.length} barrels');

    expect(exported, greaterThan(100),
        reason: 'the walk must actually reach the barrels\' exports');
    expect(found, isEmpty);
  });

  test('the export walk finds what at_chops itself exposes', () async {
    final library = await libraryAt('package:at_chops/at_chops.dart');
    final found = [
      for (final element in library.exportNamespace.definedNames2.values)
        ...exposures(element)
    ];
    print('the control matched: '
        '${found.where((f) => f.startsWith('AtChopsImpl')).toList()}');

    expect(found, contains('AtChopsImpl itself'),
        reason: 'an exported banned type');
    expect(found, contains(startsWith('AtChopsImpl.atChopsKeys: AtChopsKeys')),
        reason: 'a member returning one');
    expect(
        found,
        contains(
            allOf(startsWith('AtChopsImpl.new: '), contains('AtChopsKeys'))),
        reason: 'a constructor taking one');
  });

  test('at_auth and at_client use no AtChops', () {
    var files = 0;
    final found = <String>[];
    for (final root in ['../at_client/lib', '../at_auth/lib']) {
      for (final file in Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        files++;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (token.hasMatch(lines[i])) {
            found.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    print('read $files library files');

    expect(files, greaterThan(100),
        reason: 'the walk must actually reach both libraries');
    expect(found, isEmpty);
  });

  test('the source walk finds the AtChops at_chops declares', () async {
    final barrel = await Isolate.resolvePackageUri(
        Uri.parse('package:at_chops/at_chops.dart'));
    final lib = File.fromUri(barrel!).parent;
    final found = [
      for (final file in lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        for (final line in file.readAsLinesSync())
          if (token.hasMatch(line)) line.trim()
    ];
    print('the control matched, first: ${found.first}');

    expect(found, contains(contains('class AtChopsImpl')));
  });
}
