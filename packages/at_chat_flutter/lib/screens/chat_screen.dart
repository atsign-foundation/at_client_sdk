import 'package:at_chat_flutter/models/message_model.dart';
import 'package:at_chat_flutter/services/chat_service.dart';
import 'package:at_chat_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:at_chat_flutter/widgets/incoming_message_bubble.dart';
import 'package:at_chat_flutter/widgets/outgoing_message_bubble.dart';
import 'package:at_chat_flutter/widgets/send_message.dart';

// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/services/size_config.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

/// Widget to display chats as a screen or a bottom sheet.

class ChatScreen extends StatefulWidget {
  /// [height] specifies the height of bottom sheet/screen,
  final double? height;

  /// [isScreen] toggles the screen behaviour to adapt for screen or bottom sheet,
  final bool isScreen;

  /// [outgoingMessageColor] defines the color of outgoing message color,
  final Color outgoingMessageColor;

  /// [incomingMessageColor] defines the color of incoming message color.
  final Color incomingMessageColor;

  /// [senderAvatarColor] defines the color of sender's avatar
  final Color senderAvatarColor;

  /// [receiverAvatarColor] defines the color of receiver's avatar
  final Color receiverAvatarColor;

  /// [title] specifies the title text to be displayed.
  final String title;

  /// [hintText] specifies the hint text to be displayed in the input box.
  final String? hintText;

  const ChatScreen(
      {Key? key,
      this.height,
      this.isScreen = false,
      this.outgoingMessageColor = CustomColors.outgoingMessageColor,
      this.incomingMessageColor = CustomColors.incomingMessageColor,
      this.senderAvatarColor = CustomColors.defaultColor,
      this.receiverAvatarColor = CustomColors.defaultColor,
      this.title = 'Messages',
      this.hintText})
      : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  /// List of messages
  List<Widget> messageList = [];

  /// Input message in the chat
  String? message;

  /// Scroll controller for the chat list view
  ScrollController? _scrollController;

  /// Instance of chat service
  late ChatService _chatService;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _chatService = ChatService();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      await _chatService.getChatHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(10.toHeight),
        topRight: Radius.circular(10.toHeight),
      ),
      child: Container(
        height: widget.height ?? SizeConfig().screenHeight * 0.8,
        margin: widget.isScreen
            ? const EdgeInsets.all(0.0)
            : const EdgeInsets.only(top: 10.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(10.toHeight),
            topRight: Radius.circular(10.toHeight),
          ),
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black87
              : Colors.white,
          boxShadow: const [
            BoxShadow(
              color: Colors.grey,
              offset: Offset(0.0, 1.0),
              blurRadius: 10.0,
            ),
          ],
        ),
        child: Column(
          children: [
            (widget.isScreen)
                ? Container()
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            widget.title,
                            style: const TextStyle(
                                color: Colors.black, fontSize: 14),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: const Text(
                            'Close',
                            style: TextStyle(
                                color: Color(0xffFC7B30), fontSize: 14),
                          ),
                        ),
                      )
                    ],
                  ),
            Expanded(
                child: StreamBuilder<List<Message>>(
                    stream: _chatService.chatStream,
                    initialData: _chatService.chatHistory,
                    builder: (context, snapshot) {
                      return (snapshot.connectionState ==
                              ConnectionState.waiting)
                          ? const Center(
                              child: CircularProgressIndicator(),
                            )
                          : (snapshot.data == null || snapshot.data!.isEmpty)
                              ? const Center(
                                  child: Text('No chat history found'),
                                )
                              : ListView.builder(
                                  reverse: true,
                                  controller: _scrollController,
                                  shrinkWrap: true,
                                  itemCount: snapshot.data!.length,
                                  itemBuilder: (context, index) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10.0),
                                      child: snapshot.data![index].type ==
                                              MessageType.incoming
                                          ? IncomingMessageBubble(
                                              message: snapshot.data![index],
                                              color:
                                                  widget.incomingMessageColor,
                                              avatarColor:
                                                  widget.senderAvatarColor,
                                            )
                                          : OutgoingMessageBubble(
                                              (id) async {
                                                var result = await _chatService
                                                    .deleteSelectedMessage(id);
                                                if (context.mounted) {
                                                  Navigator.of(context).pop();
                                                }

                                                var message = result
                                                    ? 'Message is deleted'
                                                    : 'Failed to delete';
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(SnackBar(
                                                          content:
                                                              Text(message)));
                                                }
                                              },
                                              message: snapshot.data![index],
                                              color:
                                                  widget.outgoingMessageColor,
                                              avatarColor:
                                                  widget.receiverAvatarColor,
                                            ),
                                    );
                                  });
                    })),
            _buildMessageInputWidget(),
            //Make sure view inside SafeArea
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInputWidget() {
    return SendMessage(
      messageCallback: (s) {
        message = s;
      },
      hintText: widget.hintText,
      onSend: () async {
        if (message != '') {
          await _chatService.sendMessage(message);
        }
      },
      onMediaPressed: showImagePicker,
    );
  }

  void showImagePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowCompression: true,
      withData: true,
    );
    if ((result?.files ?? []).isNotEmpty) {
      final file = File(result!.files.first.path!);
      if (mounted) await _chatService.sendImageFile(context, file);
    } else {
      // User canceled the picker
    }
  }
}
