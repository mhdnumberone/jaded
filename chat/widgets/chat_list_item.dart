// lib/presentation/chat/widgets/chat_list_item.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl; // لتنسيق الوقت

import '../../../data/models/chat/chat_conversation.dart';

class ChatListItem extends StatelessWidget {
  final ChatConversation conversation;
  final VoidCallback onTap;

  const ChatListItem({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dateToFormat =
        DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (dateToFormat == today) {
      return intl.DateFormat.Hm().format(timestamp); //  'HH:mm' e.g., 14:30
    } else if (dateToFormat == yesterday) {
      return 'الأمس';
    } else if (now.difference(timestamp).inDays < 7) {
      return intl.DateFormat.E('ar')
          .format(timestamp); // اسم اليوم، e.g. 'السبت'
    } else {
      return intl.DateFormat.yMd('ar').format(timestamp); // 'd/M/yyyy'
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // استخدم conversationTitle بدلاً من userName
    final title = conversation.conversationTitle;
    final lastMessage = conversation.lastMessageText ?? 'لا توجد رسائل بعد';
    final time = _formatTimestamp(conversation.lastMessageTimestamp);

    // تحديد ما إذا كانت الرسالة الأخيرة من المستخدم الحالي
    // final bool isLastMessageFromCurrentUser = conversation.lastMessageSenderAgentCode == currentAgentCode; // Need currentAgentCode
    // يمكنك إضافة "أنت: " إذا كانت من المستخدم الحالي

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.primaryColor.withOpacity(0.1),
        foregroundColor: theme.primaryColor,
        // يمكنك استخدام الحرف الأول من العنوان أو أيقونة عامة
        child: Text(
          title.isNotEmpty ? title[0].toUpperCase() : 'C',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      title: Text(
        title,
        style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 16.5),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        lastMessage,
        style: GoogleFonts.cairo(
          fontSize: 13.5,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        time,
        style: GoogleFonts.cairo(
          fontSize: 12,
          color: isDark ? Colors.grey[500] : Colors.grey[500],
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }
}
