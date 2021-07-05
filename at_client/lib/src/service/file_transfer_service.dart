import 'dart:io';

import 'package:at_client/src/stream/file_transfer_object.dart';
import 'package:at_client/src/util/constants.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive_io.dart';

class FileTransferService {
  Future<dynamic> uploadToFileBin(
      List<int> file, String container, String fileName) async {
    try {
      var response = await http.post(
        Uri.parse(TextConstants.FILEBIN_URL + '$container/' + fileName),
        body: file,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<String> downloadFromFileBin(
      FileTransferObject fileTransferObject, String downloadPath) async {
    try {
      var response = await http.get(Uri.parse(fileTransferObject.fileUrl));
      var archive = ZipDecoder().decodeBytes(response.bodyBytes);

      var tempDirectory =
          await Directory(downloadPath).createTemp('encrypted-files');
      for (var file in archive) {
        var unzippedFile = file.content as List<int>;
        var encryptedFile = File(tempDirectory.path + '/' + file.name);
        encryptedFile.writeAsBytesSync(unzippedFile);
      }

      return tempDirectory.path;
    } catch (e) {
      print('error in downloading file: $e');
      return '';
    }
  }
}
