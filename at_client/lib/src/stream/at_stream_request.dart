
class AtStreamRequest {
  String receiverAtSign;
  String filePath;
  Function onDone;
  Function onError;

  AtStreamRequest(
      this.receiverAtSign, this.filePath, this.onDone, this.onError);
}