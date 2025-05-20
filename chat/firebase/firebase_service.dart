import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/chat/chat_conversation.dart';
import '../../../data/models/chat/chat_message.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final _uuid = Uuid();

  // Initialize Firebase (called after google-services.json is added and Firebase.initializeApp())
  Future<void> initialize() async {
    print(
        "FirebaseService initialized. Ensure Firebase.initializeApp() was called.");
  }

  // User operations
  Future<void> createUserRecord(String userId,
      {Map<String, dynamic>? userData}) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
        ...?userData,
      });
    } catch (e) {
      print("Error creating user record: $e");
      // Handle error appropriately
    }
  }

  Future<Map<String, dynamic>?> getUserRecord(String userId) async {
    try {
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
    } catch (e) {
      print("Error fetching user record: $e");
    }
    return null;
  }

  // Chat operations
  Stream<List<ChatConversation>> getChatsStream(String userId) {
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: userId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return ChatConversation.fromMap({
                'id': doc.id,
                'title': data['title'] ?? 'محادثة جديدة',
                'participants': List<String>.from(data['participants'] ?? []),
                'lastMessage': data['lastMessage'],
                'createdAt': data['createdAt']?.toDate(),
                'updatedAt': data['updatedAt']?.toDate(),
              });
            }).toList());
  }

  Future<String?> createChat(List<String> participantIds,
      {String? title}) async {
    try {
      // Sort participant IDs to create a consistent chat ID
      participantIds.sort();
      String chatId =
          participantIds.join('_'); // Simple way to generate a chat ID

      // Check if chat already exists
      DocumentSnapshot chatDoc =
          await _firestore.collection('chats').doc(chatId).get();
      if (chatDoc.exists) {
        return chatId; // Chat already exists
      }

      await _firestore.collection('chats').doc(chatId).set({
        'participants': participantIds,
        'title': title ?? 'محادثة جديدة',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return chatId;
    } catch (e) {
      print("Error creating chat: $e");
    }
    return null;
  }

  // Message operations
  Stream<List<ChatMessage>> getMessagesStream(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp',
            descending: true) // Or false for chronological order
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return ChatMessage(
                id: doc.id,
                senderId: data['senderId'] ?? '',
                text: data['text'],
                fileUrl: data['fileUrl'],
                fileName: data['fileName'],
                fileSize: data['fileSize'],
                messageType:
                    _getMessageTypeFromString(data['messageType'] ?? 'text'),
                timestamp: data['timestamp']?.toDate() ?? DateTime.now(),
                isSentByCurrentUser: false, // Will be set by the UI
              );
            }).toList());
  }

  MessageType _getMessageTypeFromString(String type) {
    switch (type) {
      case 'image':
        return MessageType.image;
      case 'video':
        return MessageType.video;
      case 'audio':
        return MessageType.audio;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }

  String _getStringFromMessageType(MessageType type) {
    switch (type) {
      case MessageType.image:
        return 'image';
      case MessageType.video:
        return 'video';
      case MessageType.audio:
        return 'audio';
      case MessageType.file:
        return 'file';
      default:
        return 'text';
    }
  }

  Future<void> sendMessage(String chatId, ChatMessage message) async {
    try {
      final messageId = message.id.isEmpty ? _uuid.v4() : message.id;

      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .set({
        'senderId': message.senderId,
        'text': message.text,
        'fileUrl': message.fileUrl,
        'fileName': message.fileName,
        'fileSize': message.fileSize,
        'messageType': _getStringFromMessageType(message.messageType),
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      // Update chat's last message and updatedAt timestamp
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': {
          'text': message.text ?? message.fileName ?? 'مرفق',
          'timestamp': FieldValue.serverTimestamp(),
          'senderId': message.senderId,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Error sending message: $e");
      rethrow;
    }
  }

  Future<String?> uploadFileToStorage(PlatformFile file, String chatId) async {
    try {
      if (file.bytes == null && file.path == null) {
        throw Exception("No file data available");
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final storageRef = _storage.ref().child('chats/$chatId/$fileName');

      UploadTask uploadTask;
      if (file.bytes != null) {
        // Upload from memory
        uploadTask = storageRef.putData(file.bytes!);
      } else {
        // Upload from file path
        final fileToUpload = File(file.path!);
        uploadTask = storageRef.putFile(fileToUpload);
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print("Error uploading file: $e");
      return null;
    }
  }

  Future<void> deleteMessage(String chatId, String messageId) async {
    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .delete();
      // Potentially update lastMessage in chat if this was the last one
    } catch (e) {
      print("Error deleting message: $e");
    }
  }

  Future<void> deleteConversation(String chatId) async {
    try {
      // Delete all messages in the conversation (subcollection)
      var messagesSnapshot = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      for (var doc in messagesSnapshot.docs) {
        await doc.reference.delete();
      }
      // Delete the chat document itself
      await _firestore.collection('chats').doc(chatId).delete();
    } catch (e) {
      print("Error deleting conversation: $e");
    }
  }

  Future<void> updateUserLastSeen(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Error updating user last seen: $e");
    }
  }
}
