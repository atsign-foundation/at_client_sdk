import 'dart:convert';

import 'package:base2e15/base2e15.dart';



void main() {
  var text = 'hello \r\n world';
  print(text);
  LineSplitter linesplitter = LineSplitter();
  var result = linesplitter.convert(text);
  print(result.length);
  var encodedText = Base2e15.encode(text.codeUnits);
  print(encodedText);
  var decodedText = utf8.decode(Base2e15.decode(encodedText));
  print(decodedText);

}