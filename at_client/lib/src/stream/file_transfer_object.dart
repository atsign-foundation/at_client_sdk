class FileTransferObject {
  final String transferId;
  final String fileName;
  final String fileEncryptionKey;
  final String fileUrl;

  FileTransferObject(
      this.transferId, this.fileName, this.fileEncryptionKey, this.fileUrl);

  @override
  String toString() {
    return toJson().toString();
  }

  Map toJson() {
    var map = {};
    map['transferId'] = transferId;
    map['fileName'] = fileName;
    map['fileEncryptionKey'] = fileEncryptionKey;
    map['fileUrl'] = fileUrl;
    return map;
  }

  static FileTransferObject? fromJson(Map json) {
    try {
      return FileTransferObject(json['transferId'], json['fileName'],
          json['fileEncryptionKey'], json['fileUrl']);
    } catch (error) {
      print('FileTransferObject.fromJson error: ' + error.toString());
    }
    return null;
  }
}
