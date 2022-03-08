import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:at_client/src/stream/file_transfer_object.dart';
import 'package:at_client/src/util/constants.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive_io.dart';

class FileTransferService {
  Future<dynamic> uploadToFileBin(
      List<int> file, String container, String fileName) async {
    try {
      var response = await http.post(
        Uri.parse(TextConstants.fileBinURL + '$container/' + fileName),
        body: file,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<dynamic> uploadToFileBinWithStreamedRequest(
      File file, String container, String fileName) async {
    try {
      var postUri =
          Uri.parse(TextConstants.FILEBIN_URL + '$container/' + fileName);
      final streamedRequest = http.StreamedRequest('POST', postUri);

      streamedRequest.contentLength = await file.length();
      file.openRead().listen((chunk) {
        streamedRequest.sink.add(chunk);
      }, onDone: () {
        streamedRequest.sink.close();
      });

      StreamedResponse response = await streamedRequest.send();
      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<FileDownloadResponse> downloadFromFileBin(
      FileTransferObject fileTransferObject, String downloadPath) async {
    try {
      var response = await http.get(Uri.parse(fileTransferObject.fileUrl));
      if (response.statusCode != 200) {
        return FileDownloadResponse(
            isError: true, errorMsg: 'error in fetching data');
      }
      var archive = ZipDecoder().decodeBytes(response.bodyBytes);

      var tempDirectory =
          await Directory(downloadPath).createTemp('encrypted-files');
      for (var file in archive) {
        var unzippedFile = file.content as List<int>;
        var encryptedFile = File(tempDirectory.path + '/' + file.name);
        encryptedFile.writeAsBytesSync(unzippedFile);
      }

      return FileDownloadResponse(filePath: tempDirectory.path);
    } catch (e) {
      print('error in downloading file: $e');
      return FileDownloadResponse(isError: true, errorMsg: e.toString());
    }
  }
}
