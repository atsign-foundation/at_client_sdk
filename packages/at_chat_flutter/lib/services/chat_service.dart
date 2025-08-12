import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chat_flutter/models/message_model.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/material.dart';

/// Service to manage the chat messages for different atsigns
class ChatService {
  ChatService._();

  static final ChatService _instance = ChatService._();

  factory ChatService() => _instance;

  /// Part of keys to identify the different AtKeys
  final String storageKey = 'chathistory.';
  final String chatKey = 'chat';
  final String chatImageKey = 'chatimg';

  /// Instance of AtClientManager
  late AtClientManager atClientManager;

  /// Root domain to use
  String? rootDomain;

  /// Root port to use
  int? rootPort;

  /// current atsign
  String? currentAtSign;

  /// Atsign chatting with current atsign
  String? chatWithAtSign;
  List<Message> chatHistory = [];
  List<dynamic> chatHistoryMessages = [];
  List<dynamic> chatHistoryMessagesOther = [];
  bool monitorStarted = false;

  // in case of group chat
  bool isGroupChat = false;
  String? groupChatId;
  List<String>? groupChatMembers = [];

  StreamController<List<Message>> chatStreamController = StreamController<List<Message>>.broadcast();

  Sink get chatSink => chatStreamController.sink;

  Stream<List<Message>> get chatStream => chatStreamController.stream;

  void disposeControllers() {
    chatStreamController.close();
  }

  /// function to set parameters passed from the calling app
  void initChatService(AtClientManager atClientManagerFromApp, String currentAtSignFromApp, String rootDomainFromApp,
      int rootPortFromApp) async {
    atClientManager = atClientManagerFromApp;
    currentAtSign = currentAtSignFromApp;
    rootDomain = rootDomainFromApp;
    rootPort = rootPortFromApp;
    await startMonitor();
  }

  /// startMonitor needs to be called at the beginning of session
  /// called again if outbound connection is dropped
  Future<bool> startMonitor() async {
    if (!monitorStarted) {
      AtClientManager.getInstance()
          .atClient
          .notificationService
          .subscribe(regex: atClientManager.atClient.getPreferences()!.namespace ?? '', shouldDecrypt: true)
          .listen((AtNotification notification) {
        _notificationCallback(notification);
      });
      monitorStarted = true;
    }
    return true;
  }

  ///Fetches privatekey for [atsign] from device keychain.
  Future<String> getPrivateKey(String atsign) async {
    var str = await KeyChainManager.getInstance().getPkamPrivateKey(atsign);
    return str!;
  }

  /// Captures and processes notifications
  void _notificationCallback(AtNotification response) async {
    var notificationKey = response.key;
    var fromAtsign = response.from;

    // ignore notification for image key delete
    if (response.operation == 'delete') {
      return;
    }
    // remove from and to atsigns from the notification key
    if (notificationKey.contains(':')) {
      notificationKey = notificationKey.split(':')[1];
    }
    notificationKey.replaceFirst(fromAtsign, '');
    notificationKey.trim();

    if (((notificationKey.startsWith(chatKey) || notificationKey.startsWith(chatImageKey)) &&
            fromAtsign == chatWithAtSign) ||
        (isGroupChat &&
            (notificationKey.startsWith(chatKey + groupChatId!) ||
                notificationKey.startsWith(chatImageKey + groupChatId!)) &&
            groupChatMembers!.contains(fromAtsign))) {
      var decryptedMessage = response.value;
      if (decryptedMessage != null) {
        chatHistoryMessagesOther = json.decode(decryptedMessage) as List;
        chatHistory = await interleave(chatHistoryMessages, chatHistoryMessagesOther);
        chatSink.add(chatHistory);
      }
    }
  }

  void setAtsignToChatWith(String? chatWithAtSignFromApp, bool isGroup, String? groupId, List<String>? groupMembers) {
    if (isGroup) {
      isGroupChat = isGroup;
      groupChatId = groupId;
      groupChatMembers = groupMembers;
    } else {
      // ignore: unnecessary_null_comparison
      if (chatWithAtSignFromApp != null) {
        if (chatWithAtSignFromApp.startsWith('@')) {
          chatWithAtSign = chatWithAtSignFromApp;
        } else {
          chatWithAtSign = '@$chatWithAtSignFromApp';
        }
      } else {
        chatWithAtSign = '';
      }
    }
  }

  Future<void> getChatHistory({String? atsign}) async {
    try {
      chatHistory = [];
      var key = AtKey()
        ..key = storageKey + (isGroupChat ? groupChatId! : '') + (chatWithAtSign ?? ' ').substring(1)
        ..sharedBy = currentAtSign!
        ..sharedWith = chatWithAtSign
        ..metadata = Metadata();
      key.metadata.ccd = true;
      var keyValue = await atClientManager.atClient.get(key).catchError((e) {
        return AtValue();
      });
      // ignore: unnecessary_null_comparison
      if (keyValue != null && keyValue.value != null) {
        chatHistoryMessages = json.decode((keyValue.value) as String) as List;
      } else {
        chatHistoryMessages = [];
      }
      // get received messages
      key.key =
          storageKey + (isGroupChat ? groupChatId! : '') + (chatWithAtSign != null ? currentAtSign! : ' ').substring(1);
      key.sharedBy = chatWithAtSign;
      key.sharedWith = currentAtSign!;
      keyValue = await atClientManager.atClient.get(key).catchError((e) {
        return AtValue();
      });
      if (keyValue.value != null) {
        chatHistoryMessagesOther = json.decode((keyValue.value) as String) as List;
      } else {
        chatHistoryMessagesOther = [];
      }
      chatHistory = await interleave(chatHistoryMessages, chatHistoryMessagesOther);
      chatSink.add(chatHistory);
    } catch (error) {
      chatSink.add(chatHistory);
    }
  }

  /// function to mix the incoming and outgoing messages by timestamp
  Future<List<Message>> interleave<T>(List a, List b) async {
    List result = [];
    final ita = a.iterator;
    final itb = b.iterator;
    bool hasa = ita.moveNext();
    bool hasb = itb.moveNext();
    Message valueA, valueB;
    while (hasa | hasb) {
      if (hasa && hasb) {
        valueA = Message.fromJson(ita.current);
        if (valueA.contentType == MessageContentType.image) {
          valueA.imageData = await getImage(valueA.message ?? '');
        }
        valueB = Message.fromJson(itb.current);
        valueB.type = MessageType.incoming;
        if (valueB.contentType == MessageContentType.image) {
          valueB.imageData = await getImage(valueB.message ?? '');
        }
        if ((valueA.time ?? 0) > (valueB.time ?? 0)) {
          result.add(valueA);
          hasa = ita.moveNext();
        } else {
          result.add(valueB);
          hasb = itb.moveNext();
        }
      } else if (hasa) {
        valueA = Message.fromJson(ita.current);
        if (valueA.contentType == MessageContentType.image) {
          valueA.imageData = await getImage(valueA.message ?? '');
        }
        result.add(valueA);
        while (hasa = ita.moveNext()) {
          valueA = Message.fromJson(ita.current);
          if (valueA.contentType == MessageContentType.image) {
            valueA.imageData = await getImage(valueA.message ?? '');
          }
          result.add(valueA);
        }
      } else if (hasb) {
        valueB = Message.fromJson(itb.current);
        valueB.type = MessageType.incoming;
        if (valueB.contentType == MessageContentType.image) {
          valueB.imageData = await getImage(valueB.message ?? '');
        }
        result.add(valueB);
        while (hasb = itb.moveNext()) {
          valueB = Message.fromJson(itb.current);
          valueB.type = MessageType.incoming;
          if (valueB.contentType == MessageContentType.image) {
            valueB.imageData = await getImage(valueB.message ?? '');
          }
          result.add(valueB);
        }
      }
    }
    List<Message> finalResult = List<Message>.from(result);
    return finalResult;
  }

  Future<void> setChatHistory(Message message, {Uint8List? imageData}) async {
    try {
      var key = AtKey()
        ..key = storageKey + (isGroupChat ? groupChatId! : '') + (chatWithAtSign ?? ' ').substring(1)
        ..sharedBy = currentAtSign!
        ..sharedWith = chatWithAtSign
        ..metadata = Metadata();
      key.metadata.ccd = true;
      key.metadata.ttr = -1;

      chatHistoryMessages.insert(0, message.toJson());
      if (message.contentType == MessageContentType.image) {
        message.imageData = imageData ?? Uint8List(0);
      }
      chatHistory.insert(0, message);
      chatSink.add(chatHistory);
      await atClientManager.atClient.put(key, json.encode(chatHistoryMessages));
    } catch (e) {
      chatSink.add([]);
    }
  }

  Future<void> sendMessage(String? message) async {
    await setChatHistory(Message(
        id: '${currentAtSign}_${DateTime.now().millisecondsSinceEpoch}',
        message: message,
        sender: currentAtSign,
        time: DateTime.now().millisecondsSinceEpoch,
        type: MessageType.outgoing));
  }

  /// deletes self owned messages only
  Future<bool> deleteMessages() async {
    var key = AtKey()
      ..key = storageKey + (isGroupChat ? groupChatId! : '') + (chatWithAtSign ?? ' ').substring(1)
      ..sharedBy = currentAtSign!
      ..sharedWith = chatWithAtSign
      ..metadata = Metadata();
    key.metadata.ccd = true;
    try {
      for (var i = 0; i < chatHistoryMessages.length; i++) {
        var message = Message.fromJson(chatHistoryMessages[i]);
        if (message.contentType == MessageContentType.image) {
          // removing 'AtKey{' and ending '}'
          var savedKey = message.message?.substring(6, (message.message?.length ?? 1) - 1);

          var key = constructKey(savedKey ?? '');
          await atClientManager.atClient.delete(key);
        }
      }
      chatHistoryMessages = [];
      var result = await atClientManager.atClient.put(key, json.encode(chatHistoryMessages));
      await getChatHistory();
      return result;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteSelectedMessage(String? id) async {
    var key = AtKey()
      ..key = storageKey + (isGroupChat ? groupChatId! : '') + (chatWithAtSign ?? ' ').substring(1)
      ..sharedBy = currentAtSign!
      ..sharedWith = chatWithAtSign
      ..metadata = Metadata();
    key.metadata.ccd = true;

    try {
      for (var i = 0; i < chatHistoryMessages.length; i++) {
        var message = Message.fromJson(chatHistoryMessages[i]);
        if (message.id == id && message.contentType == MessageContentType.image) {
          // removing 'AtKey{' and ending '}'
          var savedKey = message.message?.substring(6, (message.message?.length ?? 1) - 1);
          var key = constructKey(savedKey ?? '');

          await atClientManager.atClient.delete(key);
        }
      }
      chatHistoryMessages.removeWhere((e) {
        var message = Message.fromJson(e);
        return message.id == id;
      });
      var result = await atClientManager.atClient.put(key, json.encode(chatHistoryMessages));
      await getChatHistory();
      return result;
    } catch (e) {
      return false;
    }
  }

  Future<void> sendImageFile(BuildContext context, File file) async {
    Uint8List imageBytes = file.readAsBytesSync();
    var size = imageBytes.length;
    if (size > 512000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Image exceeds the maximum limit of 512KB. Please try with an image of lower size.')));
    } else {
      var key = AtKey()
        ..key = chatImageKey + (isGroupChat ? groupChatId! : '') + DateTime.now().millisecondsSinceEpoch.toString()
        ..sharedBy = currentAtSign!
        ..sharedWith = chatWithAtSign
        ..metadata = Metadata();
      key.metadata.ccd = true;
      key.metadata.ttr = -1;
      key.metadata.isBinary = true;

      if (isGroupChat) {
        await Future.forEach(groupChatMembers!, (dynamic member) async {
          if (member != currentAtSign) {
            key.sharedWith = member;
            await atClientManager.atClient.put(key, imageBytes);
            // send notification for groupChat
          }
        });
      } else {
        await atClientManager.atClient.put(key, imageBytes);
        //send notification
      }
      await setChatHistory(
          Message(
            message: key.toString(),
            sender: currentAtSign,
            time: DateTime.now().millisecondsSinceEpoch,
            type: MessageType.outgoing,
            contentType: MessageContentType.image,
          ),
          imageData: imageBytes);
    }
  }

  Future<Uint8List> getImage(String savedKey) async {
    if (savedKey.startsWith('AtKey{')) {
      // removing 'AtKey{' and ending '}'
      savedKey = savedKey.substring(6, savedKey.length - 1);

      var key = constructKey(savedKey);
      var keyValue = await atClientManager.atClient.get(key).catchError((e) {
        return AtValue();
      });
      // ignore: unnecessary_null_comparison
      if (keyValue != null && keyValue.value != null) {
        return keyValue.value;
      } else {
        // return empty list
        return Uint8List(0);
      }
    } else {
      return Uint8List(0);
    }
  }

  AtKey constructKey(String savedKey) {
    var key = AtKey();
    Map<String, String> keyFields = fieldSeparator(savedKey);
    // construct key
    key.key = keyFields['key'] ?? "";
    key.sharedBy = keyFields['sharedBy'];
    key.sharedWith = keyFields['sharedWith'];
    // prepare metadata
    key.metadata = Metadata();
    key.metadata.ccd = true;
    key.metadata.ttr = -1;
    key.metadata.isBinary = true;
    return key;
  }

  Map<String, String> fieldSeparator(String data) {
    var fieldStrings = data.split(',');
    Map<String, String> keyValues = {};
    for (String value in fieldStrings) {
      var subParts = value.split(':');
      keyValues[subParts[0].trim()] = subParts[1].trim();
    }
    return keyValues;
  }
}
