class AtStreamResponse {
  AtStreamStatus? status;
  String? errorCode;
  String streamId;

  AtStreamResponse(this.streamId);

  @override
  String toString() {
    return 'AtStreamResponse{status: $status, errorCode: $errorCode, errorMessage: $errorMessage}';
  }

  String? errorMessage;
}

enum AtStreamStatus { ACK, NO_ACK, COMPLETE, ERROR }
