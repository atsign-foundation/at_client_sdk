@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'fixtures/envelope_v1_golden.dart';

void main() {
  test('envelopeV1Golden is the bytes of envelope_v1_golden.json', () {
    expect(utf8.encode(envelopeV1Golden),
        File('test/fixtures/envelope_v1_golden.json').readAsBytesSync());
  });
}
