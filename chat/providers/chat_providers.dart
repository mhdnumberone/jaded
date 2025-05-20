// lib/presentation/chat/providers/chat_providers.dart
import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_storage/firebase_storage.dart"; // Import Firebase Storage
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../core/logging/logger_provider.dart";
import "../../../data/models/chat/chat_conversation.dart";
import "../../../data/models/chat/chat_message.dart";
import "../api_service.dart";
import "auth_providers.dart"; // لـ currentAgentCodeProvider

// Provider لـ ApiService - سيكون null حتى يتوفر agentCode
final apiServiceProvider = Provider<ApiService?>((ref) {
  final firestore = FirebaseFirestore.instance;
  final storage = FirebaseStorage.instance; // Add Firebase Storage instance
  final logger =
      ref.watch(appLoggerProvider); // استخدام appLoggerProvider العام
  final agentCodeAsync = ref.watch(currentAgentCodeProvider);

  return agentCodeAsync.when(
    data: (agentCode) {
      if (agentCode != null && agentCode.isNotEmpty) {
        logger.info("apiServiceProvider",
            "Agent code available: $agentCode. Initializing ApiService.");
        // Ensure correct argument order: firestore, storage, logger, agentCode
        return ApiService(firestore, storage, logger, agentCode);
      }
      logger.warn("apiServiceProvider",
          "Agent code is null or empty. ApiService will not be available yet.");
      return null;
    },
    loading: () {
      logger.info("apiServiceProvider",
          "Agent code is loading... ApiService not yet available.");
      return null;
    },
    error: (error, stackTrace) {
      logger.error(
          "apiServiceProvider", "Error loading agent code", error, stackTrace);
      return null;
    },
  );
});

// StreamProvider للمحادثات
final chatConversationsStreamProvider =
    StreamProvider<List<ChatConversation>>((ref) {
  final agentCodeAsync = ref.watch(currentAgentCodeProvider);
  final logger = ref.watch(appLoggerProvider);
  final firestore = FirebaseFirestore.instance;
  final storage = FirebaseStorage.instance; // Add Firebase Storage instance

  return agentCodeAsync.when(
    data: (agentCode) {
      if (agentCode != null && agentCode.isNotEmpty) {
        final apiService =
            ref.read(apiServiceProvider); 
        if (apiService != null) {
          return apiService.getConversationsStream();
        }
        logger.warn("chatConversationsStreamProvider",
            "ApiService was null but agentCode is $agentCode. Creating temp instance.");
        // Ensure correct argument order: firestore, storage, logger, agentCode
        final tempApiService = ApiService(firestore, storage, logger, agentCode);
        return tempApiService.getConversationsStream();
      }
      logger.info("chatConversationsStreamProvider",
          "No agent code, returning empty stream for conversations.");
      return Stream.value([]);
    },
    loading: () {
      logger.info("chatConversationsStreamProvider",
          "Agent code loading, returning empty stream for conversations.");
      return Stream.value([]);
    },
    error: (e, s) {
      logger.error(
          "chatConversationsStreamProvider",
          "Error with agent code, returning error stream for conversations.",
          e,
          s);
      return Stream.error(e, s);
    },
  );
});

// StreamProvider للرسائل
final chatMessagesStreamProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, conversationId) {
  final agentCodeAsync = ref.watch(currentAgentCodeProvider);
  final logger = ref.watch(appLoggerProvider);
  final firestore = FirebaseFirestore.instance;
  final storage = FirebaseStorage.instance; // Add Firebase Storage instance

  return agentCodeAsync.when(
    data: (agentCode) {
      if (agentCode != null && agentCode.isNotEmpty) {
        final apiService = ref.read(apiServiceProvider);
        if (apiService != null) {
          return apiService.getMessagesStream(conversationId);
        }
        logger.warn("chatMessagesStreamProvider",
            "ApiService was null for $conversationId but agentCode is $agentCode. Creating temp instance.");
        // Ensure correct argument order: firestore, storage, logger, agentCode
        final tempApiService = ApiService(firestore, storage, logger, agentCode);
        return tempApiService.getMessagesStream(conversationId);
      }
      logger.info("chatMessagesStreamProvider",
          "No agent code, returning empty stream for messages in $conversationId.");
      return Stream.value([]);
    },
    loading: () {
      logger.info("chatMessagesStreamProvider",
          "Agent code loading, returning empty stream for messages in $conversationId.");
      return Stream.value([]);
    },
    error: (e, s) {
      logger.error(
          "chatMessagesStreamProvider",
          "Error with agent code, returning error stream for messages in $conversationId.",
          e,
          s);
      return Stream.error(e, s);
    },
  );
});

