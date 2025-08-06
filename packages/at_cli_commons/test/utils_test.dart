import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:test/test.dart';

void main() {
  String atSign = '@alice';
  String progName = 'test';
  String uniqueID = '${DateTime.now().millisecondsSinceEpoch}';

  test('test standardAtClientStoragePath without uniqueID', () {
    expect(
        standardAtClientStoragePath(
          baseDir: '/tmp',
          atSign: '@alice',
          progName: 'test',
        ),
        '/tmp/.atsign/storage/$atSign/$progName/$defaultPathUniqueID'
            .replaceAll('/', Platform.pathSeparator));
  });

  test('test standardAtClientStoragePath with uniqueID', () {
    expect(
        standardAtClientStoragePath(
          baseDir: '/tmp',
          atSign: '@alice',
          progName: 'test',
          uniqueID: uniqueID,
        ),
        '/tmp/.atsign/storage/$atSign/$progName/$uniqueID'
            .replaceAll('/', Platform.pathSeparator));
  });

  test('test standardAtClientStorageDir', () {
    Directory dir = standardAtClientStorageDir(
      atSign: atSign,
      progName: progName,
      uniqueID: uniqueID,
    );
    if (Platform.isWindows) {
      expect(
          dir,
          standardWindowsAtClientStorageDir(
            atSign: atSign,
            progName: progName,
            uniqueID: uniqueID,
          ));
    } else {
      expect(
          dir.path,
          '${getHomeDirectory()}/.atsign/storage/$atSign/$progName/$uniqueID'
              .replaceAll('/', Platform.pathSeparator));
    }
  });
}
