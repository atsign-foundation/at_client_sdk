import 'dart:convert';

import 'package:at_base2e15/at_base2e15.dart';

void main() {
  var text = 'hello \r\n world';
  print(text);
  var linesplitter = LineSplitter();
  var result = linesplitter.convert(text);
  print(result.length);
  var encodedText = Base2e15.encode(text.codeUnits);
  print(encodedText);
  var decodedText = utf8.decode(Base2e15.decode(encodedText));
  print(decodedText);
}
