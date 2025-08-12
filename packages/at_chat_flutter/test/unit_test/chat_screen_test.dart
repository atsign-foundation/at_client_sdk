import 'dart:convert';
import 'dart:typed_data';
import 'package:at_chat_flutter/models/message_model.dart';
import 'package:at_chat_flutter/services/chat_service.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAtClient extends Mock implements AtClient {
  @override
  Future<bool> put(AtKey key, dynamic value,
      {bool isDedicated = false, PutRequestOptions? putRequestOptions}) async {
    return true;
  }

  @override
  Future<bool> delete(AtKey key,
      {deleteRequestOptions, bool isDedicated = false}) async {
    return true;
  }

  @override
  Future<AtValue> get(
    AtKey key, {
    bool isDedicated = false,
    GetRequestOptions? getRequestOptions,
  }) async {
    if (key.metadata.isBinary == true) {
      return AtValue()..value = Uint8List(5);
    } else {
      var atSign = "@83apedistinct";
      return AtValue()
        ..value = json.encode([
          Message(
            id: '${atSign}_${DateTime.now().millisecondsSinceEpoch}',
            message: "Hey There!",
            sender: atSign,
            time: DateTime.now().millisecondsSinceEpoch,
            type: MessageType.outgoing,
            contentType: MessageContentType.text,
          ).toJson()
        ]);
    }
  }
}

class MockAtClientManager with Mock implements AtClientManager {
  @override
  AtClient get atClient => MockAtClient();
}

void main() {
  group('Chat Service test: ', () {
    // Test case to check retrieving chat history is successful
    test("set_atsign_to_chat_with", () {
      String atSignToChatWith = "@45expected";
      ChatService().setAtsignToChatWith(atSignToChatWith, false, null, null);
      expect(ChatService().chatWithAtSign, atSignToChatWith);
    });

    test("get_chat_history", () async {
      String atSign = "@83apedistinct";

      ChatService().currentAtSign = "@83apedistinct";

      ChatService().atClientManager = MockAtClientManager();

      await ChatService().getChatHistory(atsign: atSign);
      expect(ChatService().chatHistory.length, 2);
    });

    test("inter_leave", () async {
      var atSign = "@83apedistinct";
      var message1 = Message(
          id: '${atSign}_${DateTime.now().millisecondsSinceEpoch}',
          message: "Hello World",
          sender: atSign,
          time: DateTime.now().millisecondsSinceEpoch,
          type: MessageType.outgoing,
          contentType: MessageContentType.text);

      var message2 = Message(
          id: '${atSign}_${DateTime.now().millisecondsSinceEpoch}',
          message: "Hey There!",
          sender: atSign,
          time: DateTime.now().millisecondsSinceEpoch,
          type: MessageType.outgoing,
          contentType: MessageContentType.text);

      var a = [message1.toJson(), message2.toJson()];
      var b = [message2.toJson()];

      var res = await ChatService().interleave(a, b);

      expect(res.length, 3);
    });

    test("set_chat_history", () async {
      ChatService().chatHistory = [];
      String atSign = "@83apedistinct";
      var message = Message(
          id: '${atSign}_${DateTime.now().millisecondsSinceEpoch}',
          message: "Hello World",
          sender: atSign,
          time: DateTime.now().millisecondsSinceEpoch,
          type: MessageType.outgoing,
          contentType: MessageContentType.text);

      ChatService().currentAtSign = atSign;
      ChatService().chatWithAtSign = "@45expected";

      ChatService().atClientManager = MockAtClientManager();

      await ChatService().setChatHistory(message);
      expect(ChatService().chatHistory.length, 1);
    });
  });

  test("send_message", () async {
    ChatService().chatHistory = [];
    String atSign = "@83apedistinct";
    ChatService().currentAtSign = atSign;
    ChatService().chatWithAtSign = "@45expected";

    ChatService().atClientManager = MockAtClientManager();

    await ChatService().sendMessage("Hello World");
    expect(ChatService().chatHistory.length, 1);
  });

  test("delete_messages", () async {
    String atSign = "@83apedistinct";
    ChatService().currentAtSign = atSign;
    ChatService().chatWithAtSign = "@45expected";

    ChatService().atClientManager = MockAtClientManager();

    var res = await ChatService().deleteMessages();
    expect(res, true);
  });

  test("delete_selected_messages", () async {
    String atSign = "@83apedistinct";
    ChatService().currentAtSign = atSign;
    ChatService().chatWithAtSign = "@45expected";

    ChatService().atClientManager = MockAtClientManager();

    var res = await ChatService().deleteSelectedMessage("");
    expect(res, true);
  });

  test("get_image", () async {
    String atSign = "@83apedistinct";
    ChatService().currentAtSign = atSign;
    ChatService().chatWithAtSign = "@45expected";

    ChatService().atClientManager = MockAtClientManager();

    var savedKey = "AtKey{atSign: @83apedistinct}";

    var res = await ChatService().getImage(savedKey);
    expect(res.length, 5);
  });

  test("construct_key", () async {
    var savedKey =
        "AtKey{atSign: @83apedistinct, key: key, sharedBy: @83apedistinct, sharedwith: @45expected}";

    var res = ChatService().constructKey(savedKey);
    expect(res, isA<AtKey>());
  });

  test("field_seperator", () async {
    var savedKey =
        "AtKey{atSign: @83apedistinct, key: key, sharedBy: @83apedistinct, sharedwith: @45expected}";

    var res = ChatService().fieldSeparator(savedKey);
    expect(res, isA<Map<String, String>>());
  });
}
