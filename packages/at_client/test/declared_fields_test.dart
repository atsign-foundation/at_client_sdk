import 'package:test/test.dart';

import 'test_utils/declared_fields.dart';

/// The parse the field-classification tests share finds a field in every
/// shape it can be declared in; a shape missing here is one a new field could
/// hide in.
void main() {
  test('the parse finds a field in every shape it can be declared in', () {
    expect(fieldsDeclaredIn(declarationShapes), {
      'plain',
      'nullable',
      'generic',
      'lateField',
      'finalField',
      'splitDefault',
      'withComment',
      'callback',
      'pair',
    });
  });
}
