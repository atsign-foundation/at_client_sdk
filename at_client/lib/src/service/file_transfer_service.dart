import 'package:at_client/src/stream/file_transfer_object.dart';
import 'package:at_client/src/util/constants.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive_io.dart';

class FileTransferService {
  Future<dynamic> uploadToFileBin(
      List<int> file, String container, String fileName) async {
    try {
      var response = await http.post(
        Uri.parse(TextConstants.FILEBIN_URL),
        headers: <String, String>{'bin': container, 'filename': fileName},
        body: file,
      );
      return response;
    } catch (e) {
      print('error in uploading file: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> downloadFromFileBin(
      FileTransferObject fileTransferObject) async {
    if (fileTransferObject == null) {
      throw Exception('file transfer details not found');
    }
    var encryptedFiles = <Map<String, dynamic>>[];
    try {
      var response = await http.get(Uri.parse(fileTransferObject.fileUrl));
      var archive = ZipDecoder().decodeBytes(response.bodyBytes);

      for (var file in archive) {
        var unzippedFile = file.content as List<int>;
        var fileObject = {'name': file.name, 'file': unzippedFile};
        encryptedFiles.add(fileObject);
      }

      return encryptedFiles;
    } catch (e) {
      print('error in downloading file: $e');
      return [];
    }
  }
}
