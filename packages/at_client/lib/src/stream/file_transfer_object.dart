class FileTransferObject {
  final String transferId;
  final List<FileStatus> fileStatus;
  final String fileEncryptionKey;
  final String fileUrl;
  final String sharedWith;
  bool? sharedStatus;
  DateTime? date;
  String? error;

  FileTransferObject(this.transferId, this.fileEncryptionKey, this.fileUrl,
      this.sharedWith, this.fileStatus,
      {this.date, this.error}) {
    date ??= DateTime.now();
  }

  @override
  String toString() {
    return toJson().toString();
  }

  Map toJson() {
    var map = {};
    map['transferId'] = transferId;
    map['fileEncryptionKey'] = fileEncryptionKey;
    map['fileUrl'] = fileUrl;
    map['sharedWith'] = sharedWith;
    map['sharedStatus'] = sharedStatus;
    map['fileStatus'] = fileStatus;
    map['date'] = date!.toUtc().toString();
    map['error'] = error;
    return map;
  }

  static FileTransferObject? fromJson(Map json) {
    try {
      var fileStatus = <FileStatus>[];
      json['fileStatus'].forEach((file) {
        fileStatus.add(FileStatus.fromJson(file)!);
      });

      return FileTransferObject(json['transferId'], json['fileEncryptionKey'],
          json['fileUrl'], json['sharedWith'], fileStatus,
          date: DateTime.parse(json['date']).toLocal())
        ..sharedStatus = json['sharedStatus']
        ..error = json['error'];
    } catch (error) {
      // ignore: prefer_interpolation_to_compose_strings
      print('FileTransferObject.fromJson error: ' + error.toString());
    }
    return null;
  }
}

class FileStatus {
  String? fileName;
  bool? isUploaded;
  int? size;
  String? error;

  FileStatus(
      {required this.fileName,
      this.isUploaded = false,
      required this.size,
      this.error});

  Map toJson() {
    var map = {};
    map['fileName'] = fileName;
    map['isUploaded'] = isUploaded;
    map['size'] = size;
    map['error'] = error;
    return map;
  }

  static FileStatus? fromJson(Map json) {
    try {
      return FileStatus(
          fileName: json['fileName'],
          isUploaded: json['isUploaded'],
          size: json['size'],
          error: json['error']);
    } catch (error) {
      // ignore: prefer_interpolation_to_compose_strings
      print('FileStatus.fromJson error: ' + error.toString());
    }
    return null;
  }
}

class FileDownloadResponse {
  String? filePath;
  bool isError;
  String? errorMsg;

  FileDownloadResponse({this.filePath, this.isError = false, this.errorMsg});
}
