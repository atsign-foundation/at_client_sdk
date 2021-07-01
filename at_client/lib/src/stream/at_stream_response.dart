class AtStreamResponse {
  AtStreamStatus? status;
  String? errorCode;
  String? errorMessage;
  String streamId;

  AtStreamResponse(this.streamId);


  @override
  String toString() {
    return 'AtStreamResponse{streamId: $streamId, status: $status, errorCode: $errorCode, errorMessage: $errorMessage}';
  }

}

enum AtStreamStatus { ACK, NO_ACK, COMPLETE, ERROR, CANCELLED }
