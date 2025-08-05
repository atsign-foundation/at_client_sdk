# at_utf7

<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

This is a fork of [utf7](https://pub.dev/packages/utf7) that was
created to provide a null safety dependency for downstream atPlatform
libraries.

Provides methods to encode/decode utf-7 strings or adapt the modified base64 for custom methods.

## Usage

A simple usage example:

```dart
import 'package:utf7/utf7.dart';

main() {
  // encode/decode strings
  print(Utf7.encode("ûtf-8 chäräctérs")); // +APs-tf-8 ch+AOQ-r+AOQ-ct+AOk-rs
  print(Utf7.decode("+APs-tf-8 ch+AOQ-r+AOQ-ct+AOk-rs")); // ûtf-8 chäräctérs
  // encodeAll additionally encodes characters that could be control characters
  // wherever the encoded string is used
  print(Utf7.encodeAll("A b\r\nc\$")); // A+ACA-b+AA0ACg-c+ACQ-

  // encode/decode modified base64 sequences (the part between + and -)
  print(Utf7.encodeModifiedBase64("û")); // AOQ
  print(Utf7.decodeModifiedBase64("AOQ")); // û
}
```
