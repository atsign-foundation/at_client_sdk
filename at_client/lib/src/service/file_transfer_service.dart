import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:at_client/src/stream/file_transfer_object.dart';
import 'package:at_client/src/util/constants.dart';
import 'package:http/http.dart' as http;

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
          Uri.parse(TextConstants.fileBinURL + '$container/' + fileName);
      final streamedRequest = http.StreamedRequest('POST', postUri);

      streamedRequest.contentLength = await file.length();
      file.openRead().listen((chunk) {
        streamedRequest.sink.add(chunk);
      }, onDone: () {
        streamedRequest.sink.close();
      });

      http.StreamedResponse response = await streamedRequest.send();
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
        var encryptedFile =
            File(tempDirectory.path + Platform.pathSeparator + file.name);
        encryptedFile.writeAsBytesSync(unzippedFile);
      }

      return FileDownloadResponse(filePath: tempDirectory.path);
    } catch (e) {
      print('error in downloading file: $e');
      return FileDownloadResponse(isError: true, errorMsg: e.toString());
    }
  }

  Future downloadFromFileBinUsingStream(
      FileTransferObject fileTransferObject, String downloadPath) async {
    final Completer<FileDownloadResponse> completer =
        Completer<FileDownloadResponse>();
    try {
      var httpClient = http.Client();
      var request = http.Request('GET', Uri.parse(fileTransferObject.fileUrl));
      var response = httpClient.send(request);

      List<List<int>> chunks = [];
      int downloaded = 0;
      late StreamSubscription downloadSubscription;

      downloadSubscription =
          response.asStream().listen((http.StreamedResponse r) {
        r.stream.listen((List<int> chunk) {
          chunks.add(chunk);
          downloaded += chunk.length;
        }, onDone: () async {
          ///using [downloaded] as contentlength here.
          final Uint8List bytes = Uint8List(downloaded);

          int offset = 0;
          for (List<int> chunk in chunks) {
            bytes.setRange(offset, offset + chunk.length, chunk);
            offset += chunk.length;
          }

          downloadSubscription.cancel();

          var archive = ZipDecoder().decodeBytes(bytes);
          var tempDirectory =
              await Directory(downloadPath).createTemp('encrypted-files');
          for (var file in archive) {
            var unzippedFile = file.content as List<int>;
            var encryptedFile =
                File(tempDirectory.path + Platform.pathSeparator + file.name);
            encryptedFile.writeAsBytesSync(unzippedFile);
          }

          completer.complete(
            FileDownloadResponse(filePath: tempDirectory.path),
          );
        }, onError: () {
          completer.complete(
            FileDownloadResponse(
                isError: true, errorMsg: 'Fail to download file.'),
          );
        });
      });

      return completer.future;
    } catch (e) {
      print('error in downloading file: $e');
      completer.complete(
        FileDownloadResponse(isError: true, errorMsg: e.toString()),
      );
    }
  }
}
