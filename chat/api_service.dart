// lib/presentation/chat/api_service.dart
import "dart:async";
import "dart:io"; // Required for File operations
import "dart:math";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_storage/firebase_storage.dart"; // Import Firebase Storage
import "package:file_picker/file_picker.dart"; // Required for PlatformFile
import "package:path/path.dart" as p; // For path manipulation

import "../../core/logging/logger_service.dart";
import "../../data/models/chat/chat_conversation.dart";
import "../../data/models/chat/chat_message.dart";

class ApiService {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage; // Add Firebase Storage instance
  final LoggerService _logger;
  final String _currentAgentCode;

  String get currentAgentCodeValue => _currentAgentCode;

  ApiService(this._firestore, this._storage, this._logger, this._currentAgentCode) {
    if (_currentAgentCode.isEmpty) {
      _logger.error("ApiService:Constructor",
          "CRITICAL: ApiService initialized with an empty agent code!");
    }
    _logger.info("ApiService:Constructor",
        "ApiService initialized for agent: $_currentAgentCode");
  }

  // Method to upload file to Firebase Storage
  Future<String?> uploadFileToStorage(PlatformFile platformFile, String conversationId) async {
    if (platformFile.path == null) {
      _logger.error("ApiService:uploadFileToStorage", "File path is null for ${platformFile.name}");
      return null;
    }
    File file = File(platformFile.path!);
    String fileName = "${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}";
    String filePath = "chat_attachments/$conversationId/$fileName";

    _logger.info("ApiService:uploadFileToStorage", "Attempting to upload ${platformFile.name} to $filePath");

    try {
      UploadTask uploadTask = _storage.ref().child(filePath).putFile(file);
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();
      _logger.info("ApiService:uploadFileToStorage", "File ${platformFile.name} uploaded successfully. URL: $downloadUrl");
      return downloadUrl;
    } on FirebaseException catch (e, s) {
      _logger.error("ApiService:uploadFileToStorage", "FirebaseException during upload for ${platformFile.name}: ${e.message}", e, s);
      return null;
    } catch (e, s) {
      _logger.error("ApiService:uploadFileToStorage", "Generic error during upload for ${platformFile.name}", e, s);
      return null;
    }
  }

  Stream<List<ChatConversation>> getConversationsStream() {
    _logger.info("ApiService:getConversationsStream",
        "Fetching conversations for agent: $_currentAgentCode, excluding those marked as deleted for this agent.");
    return _firestore
        .collection("conversations")
        .where("participants", arrayContains: _currentAgentCode) // User must be a participant
        .where("deletedForUsers.$_currentAgentCode", isNotEqualTo: true) // Exclude if marked deleted for this user
        .orderBy("updatedAt", descending: true)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        _logger.info(
            "ApiService:getConversationsStream", "No active conversations found for $_currentAgentCode.");
        return <ChatConversation>[];
      }
      _logger.debug("ApiService:getConversationsStream",
          "Received ${snapshot.docs.length} active conversations for $_currentAgentCode.");
      return snapshot.docs
          .map((doc) => ChatConversation.fromFirestore(
              doc as DocumentSnapshot<Map<String, dynamic>>, _currentAgentCode))
          .toList();
    }).handleError((error, stackTrace) {
      _logger.error("ApiService:getConversationsStream", "Error in stream for $_currentAgentCode",
          error, stackTrace);
      return <ChatConversation>[];
    });
  }

  Stream<List<ChatMessage>> getMessagesStream(String conversationId) {
    _logger.info("ApiService:getMessagesStream",
        "Fetching for conversation $conversationId");
    if (conversationId.isEmpty) {
      _logger.warn("ApiService:getMessagesStream",
          "Received empty conversationId. Returning empty stream.");
      return Stream.value([]);
    }
    // Note: Messages are not soft-deleted individually in this scheme.
    // If a conversation is soft-deleted for a user, they won't see it, thus won't fetch its messages.
    return _firestore
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .orderBy("timestamp", descending: false)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        _logger.info("ApiService:getMessagesStream",
            "No messages found for $conversationId.");
        return <ChatMessage>[];
      }
      _logger.debug("ApiService:getMessagesStream",
          "Received ${snapshot.docs.length} messages for $conversationId.");
      return snapshot.docs
          .map((doc) => ChatMessage.fromFirestore(
              doc as DocumentSnapshot<Map<String, dynamic>>, _currentAgentCode))
          .toList();
    }).handleError((error, stackTrace) {
      _logger.error("ApiService:getMessagesStream",
          "Error in stream for $conversationId", error, stackTrace);
      return <ChatMessage>[];
    });
  }

  Future<ChatParticipantInfo?> getAgentInfo(String agentCodeToFetch) async {
    _logger.info("ApiService:getAgentInfo",
        "Fetching info for agent_code: $agentCodeToFetch");
    if (agentCodeToFetch.isEmpty) {
      _logger.warn(
          "ApiService:getAgentInfo", "Received empty agentCodeToFetch.");
      return null;
    }
    try {
      final doc = await _firestore
          .collection("agent_identities")
          .doc(agentCodeToFetch)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        _logger.debug("ApiService:getAgentInfo",
            "Agent $agentCodeToFetch found. DisplayName: ${data["displayName"]}");
        return ChatParticipantInfo(
          agentCode: agentCodeToFetch,
          displayName: data["displayName"] as String? ?? agentCodeToFetch,
        );
      }
      _logger.warn("ApiService:getAgentInfo",
          "Agent info not found for $agentCodeToFetch in 'agent_identities'.");
      return null;
    } catch (e, s) {
      _logger.error("ApiService:getAgentInfo",
          "Error fetching agent info for $agentCodeToFetch", e, s);
      return null;
    }
  }

  Future<String?> createOrGetConversationWithParticipants(
      List<String> participantAgentCodes,
      Map<String, ChatParticipantInfo> participantInfoMapInput,
      {String? groupTitle}) async {
    _logger.info("ApiService:createOrGetConversation",
        "Attempting with initial participants: $participantAgentCodes. Current user: $_currentAgentCode");

    final allParticipantsSorted = List<String>.from(participantAgentCodes);
    if (!allParticipantsSorted.contains(_currentAgentCode)) {
      allParticipantsSorted.add(_currentAgentCode);
    }
    allParticipantsSorted.sort();

    _logger.debug("ApiService:createOrGetConversation",
        "All sorted participants: $allParticipantsSorted");

    var finalParticipantInfoMap =
        Map<String, ChatParticipantInfo>.from(participantInfoMapInput);
    if (!finalParticipantInfoMap.containsKey(_currentAgentCode)) {
      final currentUserInfo = await getAgentInfo(_currentAgentCode);
      if (currentUserInfo != null) {
        finalParticipantInfoMap[_currentAgentCode] = currentUserInfo;
      } else {
        _logger.warn("ApiService:createOrGetConversation",
            "Could not fetch current user info for $_currentAgentCode. Using fallback.");
        finalParticipantInfoMap[_currentAgentCode] = ChatParticipantInfo(
            agentCode: _currentAgentCode,
            displayName:
                "أنا (${_currentAgentCode.substring(0, min(3, _currentAgentCode.length))}..)");
      }
    }
    for (String code in allParticipantsSorted) {
      if (!finalParticipantInfoMap.containsKey(code)) {
        final info = await getAgentInfo(code);
        if (info != null) {
          finalParticipantInfoMap[code] = info;
        } else {
          _logger.error("ApiService:createOrGetConversation",
              "Could not fetch participant info for $code.");
          return null;
        }
      }
    }

    // When creating/getting a conversation, we should also check the deletedForUsers status
    // If a 2-party conversation exists but is marked deleted for the current user, we might want to "un-delete" it or create a new one.
    // For now, let's assume if it exists, we return it, and the UI handles showing it if not deleted.
    // The getConversationsStream will filter it out if it's marked deleted.
    // If we want to "un-delete" upon trying to re-open, that logic would be here.
    // For simplicity, let's stick to the current behavior: if it exists, return its ID.
    // The client will then try to fetch it via getConversationsStream which will filter it if deleted.
    // This might lead to a situation where a user tries to open a chat that then disappears.
    // A better approach might be to check deletedForUsers here and if true for current user, update it to false.

    if (allParticipantsSorted.length == 2) {
      _logger.debug("ApiService:createOrGetConversation",
          "Checking for existing 2-party conversation.");
      QuerySnapshot existingConversation = await _firestore
          .collection("conversations")
          .where("participants", isEqualTo: allParticipantsSorted)
          // No filter for deletedForUsers here, as we want to find it even if soft-deleted by one party.
          .limit(1)
          .get();

      if (existingConversation.docs.isNotEmpty) {
        final doc = existingConversation.docs.first;
        final docId = doc.id;
        final data = doc.data() as Map<String, dynamic>?;
        final deletedForUsers = data?["deletedForUsers"] as Map<String, dynamic>?;

        // If it was deleted by the current user, undelete it by removing the flag.
        if (deletedForUsers != null && deletedForUsers[_currentAgentCode] == true) {
          _logger.info("ApiService:createOrGetConversation",
              "Found existing 2-party conversation $docId, previously deleted by $_currentAgentCode. Undeleting.");
          await _firestore.collection("conversations").doc(docId).update({
            "deletedForUsers.$_currentAgentCode": FieldValue.delete(), // Remove the flag
            "updatedAt": FieldValue.serverTimestamp()
          });
        }
        _logger.info("ApiService:createOrGetConversation",
            "Found/Reactivated existing 2-party conversation: $docId");
        return docId;
      }
    }

    _logger.info("ApiService:createOrGetConversation",
        "No existing suitable conversation found or it's a group chat. Creating new one.");
    final now = DateTime.now();

    final newConversation = ChatConversation(
      id: "", // Firestore will generate ID
      participants: allParticipantsSorted,
      participantInfo: finalParticipantInfoMap,
      conversationTitle: groupTitle ??
          (allParticipantsSorted.length > 2
              ? "مجموعة جديدة (${allParticipantsSorted.length})"
              : "محادثة"), // Default title
      lastMessageText: "تم إنشاء المحادثة.",
      lastMessageTimestamp: now,
      lastMessageSenderAgentCode: _currentAgentCode, // Or system message
      createdAt: now,
      updatedAt: now,
      deletedForUsers: {}, // Initialize with empty map
    );

    try {
      final docRef = await _firestore
          .collection("conversations")
          .add(newConversation.toFirestore());
      _logger.info("ApiService:createOrGetConversation",
          "Successfully created new conversation with ID: ${docRef.id}");
      return docRef.id;
    } catch (e, stackTrace) {
      _logger.error("ApiService:createOrGetConversation",
          "Failed to create new conversation in Firestore", e, stackTrace);
      return null;
    }
  }

  Future<void> sendMessage(
      String conversationId, ChatMessage messageToSend) async {
    _logger.info("ApiService:sendMessage",
        "Sending message to conversation $conversationId by agent $_currentAgentCode. Text: ${messageToSend.text ?? messageToSend.fileName ?? 'Attachment'}");

    if (conversationId.isEmpty || messageToSend.senderId != _currentAgentCode) {
      _logger.error("ApiService:sendMessage",
          "Invalid params: convId empty or senderId mismatch. ConvId: '$conversationId', Sender: '${messageToSend.senderId}', CurrentUser: '$_currentAgentCode'");
      return;
    }

    try {
      final messageData = messageToSend.toFirestore();
      messageData["timestamp"] = FieldValue.serverTimestamp(); // Use server timestamp for messages

      final messageDocRef = await _firestore
          .collection("conversations")
          .doc(conversationId)
          .collection("messages")
          .add(messageData);

      _logger.debug("ApiService:sendMessage",
          "Message document ${messageDocRef.id} added to conversation $conversationId.");

      // When a message is sent, ensure the conversation is not marked as deleted for any participant.
      // This effectively "un-deletes" the conversation for all participants if they send a message.
      Map<String, dynamic> updateData = {
        "lastMessageText":
            messageToSend.text ?? (messageToSend.fileName ?? "مرفق"),
        "lastMessageTimestamp": FieldValue.serverTimestamp(),
        "lastMessageSenderAgentCode": messageToSend.senderId,
        "updatedAt": FieldValue.serverTimestamp(),
        "deletedForUsers": {} // Clear all soft-delete flags for all users in this conversation
      };

      await _firestore.collection("conversations").doc(conversationId).update(updateData);
      _logger.info("ApiService:sendMessage",
          "Conversation $conversationId metadata updated and un-deleted for all participants.");
    } catch (e, stackTrace) {
      _logger.error(
          "ApiService:sendMessage",
          "Failed to send message to conversation $conversationId or update conversation metadata",
          e,
          stackTrace);
      rethrow;
    }
  }

  Future<bool> validateAgentCodeAgainstFirestore(
      String agentCodeToValidate) async {
    if (agentCodeToValidate.isEmpty) {
      _logger.warn("ApiService:validateAgentCode",
          "Attempted to validate an empty agent code.");
      return false;
    }
    _logger.info("ApiService:validateAgentCode",
        "Validating agent code: $agentCodeToValidate against 'agent_identities'");
    try {
      final doc = await _firestore
          .collection("agent_identities")
          .doc(agentCodeToValidate)
          .get();

      if (doc.exists) {
        _logger.info("ApiService:validateAgentCode",
            "Agent code '$agentCodeToValidate' is VALID (document exists).");
        return true;
      } else {
        _logger.warn("ApiService:validateAgentCode",
            "Agent code '$agentCodeToValidate' is INVALID (document does not exist).");
        return false;
      }
    } catch (e, s) {
      _logger.error(
          "ApiService:validateAgentCode",
          "Error occurred while validating agent code '$agentCodeToValidate'",
          e,
          s);
      return false;
    }
  }
}

