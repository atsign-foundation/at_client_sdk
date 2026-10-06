import 'dart:io';
import 'dart:isolate';

import 'package:at_client/src/crypto/encrypted_send_metadata.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// Every [Metadata] field is either one the caller of an encrypting send
/// decides, which [metadataForEncryptedSend] carries, or one an encryption or
/// the atServer produces, which it leaves out. A field at_commons adds turns the
/// first test red until it is placed in one set or the other.
void main() {
  const callerDecides = {
    'ttl',
    'ttb',
    'ttr',
    'ccd',
    'isPublic',
    'isHidden',
    'namespaceAware',
    'isBinary',
    'immutable',
  };
  const producedForTheSend = {
    'isEncrypted',
    'sharedKeyEnc',
    'pubKeyCS',
    'pubKeyHash',
    'encKeyName',
    'encAlgo',
    'ivNonce',
    'skeEncKeyName',
    'skeEncAlgo',
    'dataSignature',
    'encoding',
    'appMetadata',
    'sharedKeyStatus',
    'isCached',
    'availableAt',
    'expiresAt',
    'refreshAt',
    'createdAt',
    'updatedAt',
  };

  final fields = <String, Object? Function(Metadata)>{
    'ttl': (m) => m.ttl,
    'ttb': (m) => m.ttb,
    'ttr': (m) => m.ttr,
    'ccd': (m) => m.ccd,
    'isPublic': (m) => m.isPublic,
    'isHidden': (m) => m.isHidden,
    'namespaceAware': (m) => m.namespaceAware,
    'isBinary': (m) => m.isBinary,
    'immutable': (m) => m.immutable,
    'isEncrypted': (m) => m.isEncrypted,
    'sharedKeyEnc': (m) => m.sharedKeyEnc,
    // ignore: deprecated_member_use
    'pubKeyCS': (m) => m.pubKeyCS,
    'pubKeyHash': (m) => m.pubKeyHash,
    'encKeyName': (m) => m.encKeyName,
    'encAlgo': (m) => m.encAlgo,
    'ivNonce': (m) => m.ivNonce,
    'skeEncKeyName': (m) => m.skeEncKeyName,
    'skeEncAlgo': (m) => m.skeEncAlgo,
    'dataSignature': (m) => m.dataSignature,
    'encoding': (m) => m.encoding,
    'appMetadata': (m) => m.appMetadata,
    'sharedKeyStatus': (m) => m.sharedKeyStatus,
    'isCached': (m) => m.isCached,
    'availableAt': (m) => m.availableAt,
    'expiresAt': (m) => m.expiresAt,
    'refreshAt': (m) => m.refreshAt,
    'createdAt': (m) => m.createdAt,
    'updatedAt': (m) => m.updatedAt,
  };

  /// The instance fields a class body declares, in every shape a field can
  /// take: with or without a default, `late`, `final`, a generic type with
  /// commas, a default on the next line. Getters, operators, methods and
  /// statics are not fields. `declarationShapes` below pins the reach, and
  /// the operator there is `==`, whose `=` must not read as a default.
  Set<String> fieldsDeclaredIn(String body) => RegExp(
          r'^  (?!static |return )(?![^;=]*\b(?:get|operator)\s)'
          r'(?:late\s+|final\s+)*[A-Za-z_][\w<>,? ]*?\s+([a-zA-Z_]\w*)'
          r'(?:\s*=(?!=)\s*[^;]+)?;$',
          multiLine: true)
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet();

  /// A class body declaring a field in every shape, beside members that are
  /// not fields.
  const declarationShapes = '''
  bool plain = false;
  String? nullable;
  Map<String, dynamic>? generic;
  late String? lateField;
  final String? finalField = null;
  Duration? splitDefault =
      const Duration(days: 8);
  int get notAField => 0;
  static const String notOne = 'x';
  bool operator ==(Object other) => true;
  Map<String, dynamic> toJson() => {};
  String toString() => 'x';
''';

  test('the parse finds a field in every shape it can be declared in', () {
    expect(
        fieldsDeclaredIn(declarationShapes),
        {
          'plain',
          'nullable',
          'generic',
          'lateField',
          'finalField',
          'splitDefault',
        },
        reason: 'a shape missing here is one a new field could hide in');
  });

  /// The instance fields `class Metadata` declares in the at_commons this
  /// package resolves, read from its source.
  Future<Set<String>> declaredMetadataFields() async {
    final library = await Isolate.resolvePackageUri(
        Uri.parse('package:at_commons/at_commons.dart'));
    final source = File.fromUri(library!.resolve('src/keystore/at_key.dart'))
        .readAsStringSync();
    final body =
        RegExp(r'^class Metadata \{\n(.*?)^\}', multiLine: true, dotAll: true)
            .firstMatch(source)!
            .group(1)!;
    return fieldsDeclaredIn(body);
  }

  test('every Metadata field is classified exactly once', () async {
    final declared = await declaredMetadataFields();

    expect(declared, contains('ivNonce'),
        reason: 'the control: the parse finds Metadata\'s own fields');
    expect(fields.keys.toSet(), declared,
        reason: 'one getter per declared field, so the test below reads them '
            'all');
    expect(callerDecides.intersection(producedForTheSend), isEmpty);
    expect(declared, callerDecides.union(producedForTheSend),
        reason: 'a Metadata field neither carried nor dropped on purpose is '
            'one nobody has decided about');
  });

  test('an encrypting send carries the caller\'s fields and nothing else', () {
    final given = Metadata()
      ..ttl = 1
      ..ttb = 2
      ..ttr = 3
      ..ccd = true
      ..isPublic = true
      ..isHidden = true
      ..namespaceAware = false
      ..isBinary = true
      ..immutable = true
      ..isEncrypted = true
      ..sharedKeyEnc = 'sharedKeyEnc'
      // ignore: deprecated_member_use
      ..pubKeyCS = 'pubKeyCS'
      ..pubKeyHash = PublicKeyHash('hash', 'sha256')
      ..encKeyName = 'encKeyName'
      ..encAlgo = 'encAlgo'
      ..ivNonce = 'ivNonce'
      ..skeEncKeyName = 'skeEncKeyName'
      ..skeEncAlgo = 'skeEncAlgo'
      ..dataSignature = 'dataSignature'
      ..encoding = 'base64'
      ..appMetadata = AppMetadata(providerId: 'earlier-provider')
      ..sharedKeyStatus = 'sharedKeyStatus'
      ..isCached = true
      ..availableAt = DateTime.utc(2001)
      ..expiresAt = DateTime.utc(2002)
      ..refreshAt = DateTime.utc(2003)
      ..createdAt = DateTime.utc(2004)
      ..updatedAt = DateTime.utc(2005);
    final unset = Metadata();
    for (final MapEntry(key: name, value: read) in fields.entries) {
      expect(read(given), isNot(read(unset)),
          reason: 'the control: $name is set away from its default, so the '
              'checks below can tell carried from dropped');
    }

    final sent = metadataForEncryptedSend(given);

    for (final name in callerDecides) {
      expect(fields[name]!(sent), fields[name]!(given),
          reason: '$name is the caller\'s to decide');
    }
    for (final name in producedForTheSend) {
      expect(fields[name]!(sent), fields[name]!(unset),
          reason: '$name is produced for each send, never taken from the key');
    }
  });
}
