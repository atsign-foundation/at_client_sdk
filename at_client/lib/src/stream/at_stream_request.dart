class AtStreamRequest {
  String receiverAtSign;
  String filePath;
  int startByte = 0;
  int? fileLength;
  String? namespace;

  AtStreamRequest(this.receiverAtSign, this.filePath);
}