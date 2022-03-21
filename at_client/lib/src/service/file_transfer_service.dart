import 'dart:async';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:at_client/src/stream/file_transfer_object.dart';
import 'package:at_client/src/util/constants.dart';
import 'package:at_utils/at_logger.dart';
import 'package:http/http.dart' as http;

class FileTransferService {
  final _logger = AtSignLogger('FileTransferService');

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

  Future<FileDownloadResponse> downloadFilebinContainerZip(
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
      _logger.severe('error in downloading file: $e');
      return FileDownloadResponse(isError: true, errorMsg: e.toString());
    }
  }

  Future downloadAllFiles(
      FileTransferObject fileTransferObject, String downloadPath) async {
    final Completer<FileDownloadResponse> completer =
        Completer<FileDownloadResponse>();
    var tempDirectory =
        await Directory(downloadPath).createTemp('encrypted-files');
    var fileDownloadResponse =
        FileDownloadResponse(isError: false, filePath: tempDirectory.path);

    try {
      String filebinContainer = fileTransferObject.fileUrl;
      filebinContainer = filebinContainer.replaceFirst('/archive', '');
      filebinContainer = filebinContainer.replaceFirst('/zip', '');

      for (int i = 0; i < fileTransferObject.fileStatus.length; i++) {
        String fileName = fileTransferObject.fileStatus[i].fileName!;
        String fileUrl = filebinContainer + Platform.pathSeparator + fileName;
        var downloadResponse =
            await downloadIndividualFile(fileUrl, tempDirectory.path, fileName);
        if (downloadResponse.isError) {
          fileDownloadResponse = FileDownloadResponse(
              isError: true,
              filePath: tempDirectory.path,
              errorMsg: 'Failed to download file.');
        }
      }

      completer.complete(fileDownloadResponse);
      return completer.future;
    } catch (e) {
      completer.complete(
        FileDownloadResponse(
            isError: true, errorMsg: 'Failed to download file.'),
      );
    }
    return completer.future;
  }

  Future downloadIndividualFile(
      String fileUrl, String tempPath, String fileName) async {
    final Completer<FileDownloadResponse> completer =
        Completer<FileDownloadResponse>();
    var httpClient = http.Client();
    http.Request request;
    late Future<http.StreamedResponse> response;

    try {
      request = http.Request('GET', Uri.parse(fileUrl));
      response = httpClient.send(request);
    } catch (e) {
      throw ('Failed to fetch file details.');
    }

    late StreamSubscription downloadSubscription;
    File file = File(tempPath + Platform.pathSeparator + fileName);
    int downloaded = 0;

    try {
      downloadSubscription =
          response.asStream().listen((http.StreamedResponse r) {
        r.stream.listen(
          (List<int> chunk) {
            file.writeAsBytesSync(chunk, mode: FileMode.append);
            downloaded += chunk.length;
            // if (r.contentLength != null) {
            // print('percentage: ${(downloaded / r.contentLength!)}');
            // }
          },
          onDone: () async {
            downloadSubscription.cancel();
            completer.complete(
              FileDownloadResponse(filePath: file.path),
            );
          },
        );
      });

      return completer.future;
    } catch (e) {
      downloadSubscription.cancel();
      completer.complete(
        FileDownloadResponse(
            isError: true, errorMsg: 'Failed to download file.'),
      );
    }

    return completer.future;
  }
}
