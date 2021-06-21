class AtStreamRequest {
  String receiverAtSign;
  String filePath;
  int startByte = 0;
  int? fileLength;
  String? namespace;
  Function onDone;
  Function onError;

  AtStreamRequest(
      this.receiverAtSign, this.filePath, this.onDone, this.onError);
}
