// lib/presentation/chat/view_models/conversation_view_model.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/chat/chat_conversation.dart';
import '../../../data/repositories/firestore_repository.dart';
import 'message_view_model.dart';

/// نموذج عرض للمحادثات يتبع نمط MVVM
class ConversationViewModel extends StateNotifier<AsyncValue<List<ChatConversation>>> {
  final FirestoreRepository _repository;
  
  ConversationViewModel(this._repository) : super(const AsyncValue.loading()) {
    // بدء الاستماع لتدفق المحادثات
    _listenToConversations();
  }

  /// بدء الاستماع لتدفق المحادثات
  void _listenToConversations() {
    _repository.getConversationsStream().listen(
      (conversations) {
        // تحديث الحالة بالمحادثات الجديدة
        state = AsyncValue.data(conversations);
      },
      onError: (error, stackTrace) {
        // تحديث الحالة بالخطأ
        state = AsyncValue.error(error, stackTrace);
      }
    );
  }

  /// إنشاء محادثة جديدة أو الحصول على محادثة موجودة
  Future<String?> createOrGetConversation(
    List<String> participantAgentCodes,
    Map<String, ChatParticipantInfo> participantInfoMap,
    {String? groupTitle}
  ) async {
    return _repository.createOrGetConversation(
      participantAgentCodes,
      participantInfoMap,
      groupTitle: groupTitle
    );
  }
}

/// مزود لنموذج عرض المحادثات
final conversationViewModelProvider = StateNotifierProvider<ConversationViewModel, AsyncValue<List<ChatConversation>>>(
  (ref) {
    // الحصول على مستودع Firestore
    final repository = ref.watch(firestoreRepositoryProvider);
    
    // إنشاء نموذج عرض المحادثات
    return ConversationViewModel(repository);
  }
);
