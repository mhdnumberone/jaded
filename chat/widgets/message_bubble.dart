// lib/presentation/chat/widgets/message_bubble.dart
import "dart:io";
import "dart:typed_data";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:google_fonts/google_fonts.dart";
import "package:intl/intl.dart" as intl;
import "package:open_file/open_file.dart";
import "package:path_provider/path_provider.dart";
import "package:photo_view/photo_view.dart";
import "package:video_player/video_player.dart";

import "../../../core/logging/logger_provider.dart";
import "../../../core/utils/file_saver.dart";
import "../../../data/models/chat/chat_message.dart";

String _formatBytes(int bytes, int decimals) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  var i = (bytes.toString().length - 1) ~/ 3;
  if (i >= suffixes.length) i = suffixes.length - 1;
  return "${(bytes / (1024 * 1024 * i)).toStringAsFixed(decimals)} ${suffixes[i]}";
}

class MessageBubble extends ConsumerStatefulWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  VideoPlayerController? _videoController;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.message.messageType == MessageType.video &&
        widget.message.fileUrl != null) {
      _videoController = VideoPlayerController.networkUrl(
          Uri.parse(widget.message.fileUrl!),
        )
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
          }
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _downloadAndSaveFile(
    BuildContext context,
    String url,
    String fileName,
  ) async {
    final logger = ref.read(appLoggerProvider);
    if (!mounted) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("بدء تنزيل: $fileName", style: GoogleFonts.cairo()),
      ),
    );
    try {
      Dio dio = Dio();
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      if (response.data != null) {
        final result = await FileSaver.saveFile(
          bytes: Uint8List.fromList(response.data!),
          suggestedFileName: fileName,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result, style: GoogleFonts.cairo())),
          );
        }
        logger.info("MessageBubble", "File saved: $fileName. Result: $result");
      }
    } catch (e, s) {
      logger.error(
        "MessageBubble",
        "Error downloading/saving file: $fileName",
        e,
        s,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "فشل التنزيل: ${e.toString()}",
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });
      }
    }
  }

  Future<void> _openFile(
    BuildContext context,
    String url,
    String fileName,
  ) async {
    final logger = ref.read(appLoggerProvider);
    if (!mounted) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String localPath = "${tempDir.path}/$fileName";

      await Dio().download(
        url,
        localPath,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      final result = await OpenFile.open(localPath);

      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("فشل فتح الملف: ${result.message}"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e, s) {
      logger.error("MessageBubble", "Error opening file: $fileName", e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("خطأ: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSentByCurrentUser = widget.message.isSentByCurrentUser;
    final theme = Theme.of(context);
    final bubbleColor =
        isSentByCurrentUser
            ? theme.primaryColor.withOpacity(0.9)
            : (theme.brightness == Brightness.dark
                ? Colors.grey[800]!
                : Colors.grey[200]!);
    final textColor =
        isSentByCurrentUser
            ? Colors.white
            : (theme.brightness == Brightness.dark
                ? Colors.white.withOpacity(0.9)
                : Colors.black.withOpacity(0.87));

    final timeFormatted = intl.DateFormat.Hm(
      "ar",
    ).format(widget.message.timestamp);

    Widget messageContent;
    List<Widget> actionButtons = [];

    if (widget.message.fileUrl != null && widget.message.fileName != null) {
      actionButtons.addAll([
        IconButton(
          icon: Icon(Icons.download_outlined, color: textColor, size: 20),
          tooltip: "تنزيل الملف",
          onPressed:
              _isDownloading
                  ? null
                  : () => _downloadAndSaveFile(
                    context,
                    widget.message.fileUrl!,
                    widget.message.fileName!,
                  ),
        ),
        IconButton(
          icon: Icon(Icons.open_in_new, color: textColor, size: 20),
          tooltip: "فتح الملف",
          onPressed:
              _isDownloading
                  ? null
                  : () => _openFile(
                    context,
                    widget.message.fileUrl!,
                    widget.message.fileName!,
                  ),
        ),
      ]);
    }

    switch (widget.message.messageType) {
      case MessageType.text:
        messageContent = Text(
          widget.message.text ?? "",
          style: GoogleFonts.cairo(color: textColor, fontSize: 15),
        );
        break;
      case MessageType.image:
        if (widget.message.fileUrl != null) {
          messageContent = GestureDetector(
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => Scaffold(
                          appBar: AppBar(
                            title: Text(
                              widget.message.fileName ?? "صورة",
                              style: GoogleFonts.cairo(),
                            ),
                            backgroundColor: Colors.black,
                          ),
                          body: PhotoView(
                            imageProvider: NetworkImage(
                              widget.message.fileUrl!,
                            ),
                            loadingBuilder:
                                (_, __) => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                            backgroundDecoration: const BoxDecoration(
                              color: Colors.black,
                            ),
                          ),
                        ),
                  ),
                ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 250,
                maxWidth: MediaQuery.of(context).size.width * 0.6,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.message.fileUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder:
                      (_, child, progress) =>
                          progress == null
                              ? child
                              : Center(
                                child: CircularProgressIndicator(
                                  value:
                                      progress.expectedTotalBytes != null
                                          ? progress.cumulativeBytesLoaded /
                                              progress.expectedTotalBytes!
                                          : null,
                                ),
                              ),
                  errorBuilder:
                      (_, __, ___) => Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.broken_image, size: 50),
                      ),
                ),
              ),
            ),
          );
        } else {
          messageContent = Text(
            "[صورة غير متاحة]",
            style: GoogleFonts.cairo(color: textColor),
          );
        }
        break;
      case MessageType.video:
        if (_videoController != null && _videoController!.value.isInitialized) {
          messageContent = GestureDetector(
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => Scaffold(
                          appBar: AppBar(
                            title: Text(
                              widget.message.fileName ?? "فيديو",
                              style: GoogleFonts.cairo(),
                            ),
                            backgroundColor: Colors.black,
                          ),
                          body: Center(
                            child: AspectRatio(
                              aspectRatio: _videoController!.value.aspectRatio,
                              child: VideoPlayer(_videoController!),
                            ),
                          ),
                          floatingActionButton: FloatingActionButton(
                            onPressed:
                                () =>
                                    _videoController!.value.isPlaying
                                        ? _videoController!.pause()
                                        : _videoController!.play(),
                            child: Icon(
                              _videoController!.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                          ),
                        ),
                  ),
                ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
                Icon(Icons.play_circle_fill, size: 50, color: Colors.white70),
              ],
            ),
          );
        } else {
          messageContent = Container(
            height: 150,
            color: Colors.black,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        break;
      case MessageType.file:
        messageContent = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file, color: textColor, size: 30),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.message.fileName ?? "ملف",
                    style: GoogleFonts.cairo(color: textColor, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.message.fileSize != null)
                    Text(
                      _formatBytes(widget.message.fileSize!, 1),
                      style: GoogleFonts.cairo(
                        color: textColor.withOpacity(0.7),
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
        break;
      default:
        messageContent = Text(
          "[رسالة غير معروفة]",
          style: GoogleFonts.cairo(color: textColor),
        );
    }

    return Align(
      alignment:
          isSentByCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft:
                isSentByCurrentUser ? const Radius.circular(12) : Radius.zero,
            bottomRight:
                isSentByCurrentUser ? Radius.zero : const Radius.circular(12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isSentByCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            messageContent,
            if (_isDownloading)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: LinearProgressIndicator(
                  value: _downloadProgress,
                  backgroundColor: textColor.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...actionButtons,
                const SizedBox(width: 4),
                Text(
                  timeFormatted,
                  style: GoogleFonts.cairo(
                    color: textColor.withOpacity(0.7),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
