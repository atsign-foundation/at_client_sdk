import 'package:dart_utf7/utf7.dart';

main() {
  String string = "Tèxt cöntäînîng ûtf-8 chäräctérs";
  String encoded = Utf7.encode(string);
  String strongEncoded = Utf7.encodeAll(string);
  print("UTF-7 representation: $encoded");
  print("UTF-7 representation: $strongEncoded");
  String decoded = Utf7.decode(encoded);
  print("UTF-16 representation: $decoded");
}
