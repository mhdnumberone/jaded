// lib/presentation/chat/view_models/message_view_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logger_provider.dart';
import '../../../data/models/chat/chat_message.dart';
import '../../../data/repositories/firestore_repository.dart';
import '../../chat/providers/auth_providers.dart';

/// نموذج عرض للرسائل يدعم التحميل الكسول والصفحات
class MessageViewModel extends StateNotifier<AsyncValue<List<ChatMessage>>> {
  final FirestoreRepository _repository;
  final String _conversationId;
  final int _pageSize;
  
  // تتبع ما إذا كان هناك المزيد من الرسائل للتحميل
  bool _hasMoreMessages = true;
  
  // تتبع ما إذا كان التحميل جارٍ حاليًا
  bool _isLoadingMore = false;
  
  // تخزين أقدم رسالة تم تحميلها للاستخدام في تحميل المزيد
  DateTime? _oldestMessageTimestamp;

  MessageViewModel(this._repository, this._conversationId, {int pageSize = 20}) 
      : _pageSize = pageSize,
        super(const AsyncValue.loading()) {
    // بدء الاستماع لتدفق الرسائل
    _listenToMessages();
  }

  /// بدء الاستماع لتدفق الرسائل
  void _listenToMessages() {
    _repository.getMessagesStream(_conversationId, pageSize: _pageSize).listen(
      (messages) {
        // تحديث الحالة بالرسائل الجديدة
        state = AsyncValue.data(messages);
        
        // تحديث أقدم رسالة إذا كانت هناك رسائل
        if (messages.isNotEmpty) {
          _oldestMessageTimestamp = messages.first.timestamp;
        }
        
        // إعادة تعيين حالة التحميل
        _isLoadingMore = false;
      },
      onError: (error, stackTrace) {
        // تحديث الحالة بالخطأ
        state = AsyncValue.error(error, stackTrace);
        
        // إعادة تعيين حالة التحميل
        _isLoadingMore = false;
      }
    );
  }

  /// تحميل المزيد من الرسائل (صفحة سابقة)
  Future<void> loadMoreMessages() async {
    // التحقق من وجود المزيد من الرسائل وأن التحميل ليس جاريًا حاليًا
    if (!_hasMoreMessages || _isLoadingMore || _oldestMessageTimestamp == null) {
      return;
    }
    
    // تعيين حالة التحميل
    _isLoadingMore = true;
    
    try {
      // تحميل المزيد من الرسائل
      final newMessages = await _repository.loadMoreMessages(
        _conversationId, 
        _oldestMessageTimestamp!, 
        pageSize: _pageSize
      );
      
      // التحقق مما إذا كان هناك المزيد من الرسائل
      if (newMessages.isEmpty) {
        _hasMoreMessages = false;
        _isLoadingMore = false;
        return;
      }
      
      // تحديث أقدم رسالة
      if (newMessages.isNotEmpty) {
        _oldestMessageTimestamp = newMessages.first.timestamp;
      }
      
      // ملاحظة: لا نحتاج إلى تحديث الحالة هنا لأن تدفق الرسائل سيقوم بذلك
    } catch (e) {
      // إعادة تعيين حالة التحميل في حالة الخطأ
      _isLoadingMore = false;
    }
  }

  /// إرسال رسالة جديدة
  Future<bool> sendMessage(ChatMessage message) async {
    return _repository.sendMessage(_conversationId, message);
  }

  /// التحقق مما إذا كان هناك المزيد من الرسائل للتحميل
  bool get hasMoreMessages => _hasMoreMessages;
  
  /// التحقق مما إذا كان التحميل جارٍ حاليًا
  bool get isLoadingMore => _isLoadingMore;
}

/// مزود لنموذج عرض الرسائل
final messageViewModelProvider = StateNotifierProvider.family<MessageViewModel, AsyncValue<List<ChatMessage>>, String>(
  (ref, conversationId) {
    // الحصول على مستودع Firestore
    final repository = ref.watch(firestoreRepositoryProvider);
    
    // إنشاء نموذج عرض الرسائل
    return MessageViewModel(repository, conversationId);
  }
);

/// مزود لمستودع Firestore
final firestoreRepositoryProvider = Provider<FirestoreRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final storage = ref.watch(firebaseStorageProvider);
  final logger = ref.watch(appLoggerProvider);
  final agentCodeAsync = ref.watch(currentAgentCodeProvider);
  
  return agentCodeAsync.when(
    data: (agentCode) {
      if (agentCode != null && agentCode.isNotEmpty) {
        return FirestoreRepository(firestore, storage, logger, agentCode);
      }
      throw Exception("Agent code is null or empty");
    },
    loading: () => throw Exception("Agent code is loading"),
    error: (error, _) => throw Exception("Error loading agent code: $error"),
  );
});

/// مزود لـ Firestore
final firestoreProvider = Provider((ref) => FirebaseFirestore.instance);

/// مزود لـ Firebase Storage
final firebaseStorageProvider = Provider((ref) => FirebaseStorage.instance);
