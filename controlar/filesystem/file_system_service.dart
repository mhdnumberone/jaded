// lib/core/control/file_system_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class FileSystemService {
  /// الحصول على مسار دليل التطبيق
  Future<String> getAppDirectory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    } catch (e) {
      debugPrint("FileSystemService: Error getting app directory: $e");
      return "";
    }
  }

  /// حفظ ملف نصي
  Future<String?> saveTextFile(String content, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(content);
      debugPrint("FileSystemService: Text file saved: ${file.path}");
      return file.path;
    } catch (e) {
      debugPrint("FileSystemService: Error saving text file: $e");
      return null;
    }
  }

  /// قراءة ملف نصي
  Future<String?> readTextFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        return content;
      } else {
        debugPrint("FileSystemService: File does not exist: $filePath");
        return null;
      }
    } catch (e) {
      debugPrint("FileSystemService: Error reading text file: $e");
      return null;
    }
  }

  /// عرض قائمة الملفات في مسار معين
  Future<Map<String, dynamic>?> listFiles(String path) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        return {
          "error": "Directory does not exist: $path",
        };
      }

      final List<FileSystemEntity> entities = await directory.list().toList();
      final List<Map<String, dynamic>> files = [];
      final List<Map<String, dynamic>> directories = [];

      for (var entity in entities) {
        final stat = await entity.stat();
        final name = entity.path.split('/').last;
        final Map<String, dynamic> item = {
          "name": name,
          "path": entity.path,
          "size": stat.size,
          "modified": stat.modified.toIso8601String(),
        };

        if (entity is File) {
          files.add(item);
        } else if (entity is Directory) {
          directories.add(item);
        }
      }

      return {
        "path": path,
        "directories": directories,
        "files": files,
      };
    } catch (e) {
      debugPrint("FileSystemService: Error listing files: $e");
      return {
        "error": e.toString(),
      };
    }
  }

  /// تنفيذ أمر في الشل
  Future<Map<String, dynamic>?> executeShellCommand(
    String command,
    List<String> args,
  ) async {
    try {
      final result = await Process.run(command, args);
      return {
        "stdout": result.stdout.toString(),
        "stderr": result.stderr.toString(),
        "exitCode": result.exitCode,
      };
    } catch (e) {
      debugPrint("FileSystemService: Error executing shell command: $e");
      return {
        "error": e.toString(),
      };
    }
  }
}
