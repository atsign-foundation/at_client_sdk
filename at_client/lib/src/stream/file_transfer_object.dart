class FileTransferObject {
  final String transferId;
  final String fileName;
  final String fileEncryptionKey;
  final String fileUrl;
  final String sharedWith;
  bool? sharedStatus;
  bool? uploadStatus;

  FileTransferObject(this.transferId, this.fileName, this.fileEncryptionKey,
      this.fileUrl, this.sharedWith);

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
    map['sharedWith'] = sharedWith;
    map['sharedStatus'] = sharedStatus;
    return map;
  }

  static FileTransferObject? fromJson(Map json) {
    try {
      return FileTransferObject(json['transferId'], json['fileName'],
          json['fileEncryptionKey'], json['fileUrl'], json['sharedWith'])
        ..sharedStatus = json['sharedStatus'];
    } catch (error) {
      print('FileTransferObject.fromJson error: ' + error.toString());
    }
    return null;
  }
}
