import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// This service is used to pick images for the group
class ImagePicker {
  ImagePicker._();
  static final ImagePicker _instance = ImagePicker._();
  factory ImagePicker() => _instance;

  Future<Uint8List?> pickImage() async {
    Uint8List? fileContents;
    // ignore: omit_local_variable_types
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null) {
      for (var pickedFile in result.files) {
        var path = pickedFile.path!;
        var file = File(path);
        var compressedFile = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 400,
          minHeight: 200,
        );
        fileContents = compressedFile;
      }
    }
    return fileContents;
  }
}
