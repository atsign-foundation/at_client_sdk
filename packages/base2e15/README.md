# at_base2e15

<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

This is a fork of [base2e15](https://pub.dev/packages/base2e15) that was
created before the upstream project moved to null safety.

binary-to-text encoding schemes that represent binary data in an unicode string format, each unicode character represent 15 bits of binary data

#### Example ####

| Encoding | Data | chararacters |
|:-:|:-:|:-:|
| Plain text | Base2e15 is awesome! | 20 |
| **Base2e15** | **嗺둽嬖蟝巍媖疌켉溁닽壪** | **11** |
| Base64 | QmFzZTJlMTUgaXMgYXdlc29tZSE= | 27+1 |
 
## Mapping table
Every character represent 15 bits of data, except the last character 7 bits or 15 bits

| Binary | Unicode | Unicode Range Name |
|:-:|:-:|:-:|
| **15 bits mapping** | | |
| 0x0000 ~ 0x1935 | U+3480 ~ U+4DB5 | CJK Unified Ideographs Extension A |
| 0x1936 ~ 0x545B | U+4E00 ~ U+8925 | CJK Unified Ideographs |
| 0x545C ~ 0x7FFF | U+AC00 ~ U+D7A3 | Hangul Syllables |
| **7 bits mapping** | | |
| 0x00   ~ 0x7F | U+3400 ~ U+347F | CJK Unified Ideographs Extension A |

## Usage

A simple usage example in dart:
```dart
import 'dart:convert';
import 'package:base2e15/base2e15.dart';

main() {
  String msg = 'Base2e15 is awesome!';
  String encoded = Base2e15.encode(UTF8.encode(msg));
  String decoded = UTF8.decode(Base2e15.decode(encoded));
}
```

## Compare

| Compare | Base2e15 |  Base64 |
|:-:|:-:|:-:|
| bits per character | **15** | 6 |
| bits per char width | **7.5 (15/2)** | 6 (6/1) |
| bits per UTF8 byte | 5 (15/3) | **6 (6/1)** |
| bits per UTF16 byte | **7.5 (15/2)** | 3 (6/2) |

## Why not base2e16 ?
Unicode range `CJK Unified Ideographs Extension B` contains 42711 characters (U+20000 ~ U+2A6D6), together with the characters used by base2e15, there are more than 65536 usable characters to encode 16 bits in each character.

However, font support for `CJK Unified Ideographs Extension B` is missing in most mobile devices and using this code range will also readue the bits capacity in UTF8 and UTF16 encoding, since those characters require one more byte in UTF8 and 2 more bytes in UTF16.
