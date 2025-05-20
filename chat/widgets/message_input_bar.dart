// lib/presentation/chat/widgets/message_input_bar.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MessageInputBar extends StatefulWidget {
  final Function(String) onSendPressed;
  final VoidCallback onAttachmentPressed;

  const MessageInputBar({
    super.key,
    required this.onSendPressed,
    required this.onAttachmentPressed,
  });

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  final TextEditingController _textController = TextEditingController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      if (mounted) {
        // تحقق من أن الـ widget ما زال في الشجرة
        setState(() {
          _canSend = _textController.text.trim().isNotEmpty;
        });
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _handleSend() {
    if (_canSend) {
      widget.onSendPressed(_textController.text.trim());
      _textController.clear();
      // FocusScope.of(context).unfocus(); // لإخفاء لوحة المفاتيح بعد الإرسال
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      // لإضافة ظل طفيف
      elevation: 5.0,
      color: theme.cardColor, // استخدام لون البطاقة كخلفية أو لون السطح
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        // decoration: BoxDecoration( // يمكن إزالة هذا إذا كان لون Material كافيًا
        //   color: theme.cardColor,
        //   // border: Border(top: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!)),
        // ),
        child: Row(
          children: <Widget>[
            // زر المرفقات
            IconButton(
              icon: Icon(Icons.attach_file_outlined,
                  color: theme.primaryColor.withOpacity(0.8)),
              iconSize: 26,
              tooltip: 'إرفاق ملف',
              onPressed: widget.onAttachmentPressed,
            ),
            // حقل إدخال النص
            Expanded(
              child: TextField(
                controller: _textController,
                style: GoogleFonts.cairo(fontSize: 15.5),
                decoration: InputDecoration(
                  hintText: 'اكتب رسالتك هنا...',
                  hintStyle:
                      GoogleFonts.cairo(color: Colors.grey[500], fontSize: 15),
                  border: InputBorder.none, // إزالة الحدود الافتراضية
                  focusedBorder: InputBorder.none, // لا حدود عند التركيز
                  enabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10), // تعديل الحشو
                  // filled: true, // لا حاجة لـ filled إذا كان Container يعطي الخلفية
                  // fillColor: theme.inputDecorationTheme.fillColor,
                ),
                keyboardType: TextInputType.multiline,
                minLines: 1,
                maxLines: 5, // السماح بعدة أسطر
                textInputAction:
                    TextInputAction.send, // تغيير زر الإدخال إلى "إرسال"
                onSubmitted: (_) =>
                    _handleSend(), // الإرسال عند الضغط على "إرسال" من لوحة المفاتيح
              ),
            ),
            // زر الإرسال
            IconButton(
              icon: Icon(
                Icons.send_rounded, // أيقونة إرسال أفضل
                color: _canSend ? theme.primaryColor : Colors.grey[400],
              ),
              iconSize: 28,
              tooltip: 'إرسال',
              onPressed: _canSend
                  ? _handleSend
                  : null, // تعطيل الزر إذا لم يكن هناك نص
            ),
          ],
        ),
      ),
    );
  }
}
