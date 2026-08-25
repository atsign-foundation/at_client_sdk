import 'package:at_auth/at_auth_io.dart';
import 'package:path/path.dart' as path;
import 'package:at_commons/atsign.dart';

extension FileAtKeysIoUtil on FileAtKeysIo {
  Atsign getAtsign() {
    var filepath = filePath!('');
    var name = path.basenameWithoutExtension(filepath);
    var atSign = name.replaceAll('_key', '');
    if (atSign == "@" || atSign.isEmpty) {
      throw FormatException("Failed to parse atsign from filePath");
    }
    return atSign.toAtsign();
  }
}
