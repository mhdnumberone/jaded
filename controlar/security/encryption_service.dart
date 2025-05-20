// lib/core/controlar/security/encryption_service.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../permissions/device_info_service.dart';

/// Advanced encryption service with key rotation, multiple encryption modes,
/// and obfuscation capabilities.
class EncryptionService {
  // Dependencies
  final DeviceInfoService _deviceInfoService;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Encryption keys
  late encrypt.Key _primaryKey;
  late encrypt.Key _secondaryKey;
  late encrypt.IV _primaryIV;
  DateTime? _lastKeyRotation;

  // Encrypters
  late encrypt.Encrypter _aesEncrypter;
  late encrypt.Encrypter _salsa20Encrypter;

  // Random generator
  final Random _random = Random.secure();

  // Constants
  static const String KEY_PRIMARY = 'encryption_primary_key';
  static const String KEY_SECONDARY = 'encryption_secondary_key';
  static const String KEY_IV = 'encryption_iv';
  static const String KEY_LAST_ROTATION = 'encryption_last_rotation';

  EncryptionService({
    DeviceInfoService? deviceInfoService,
  }) : _deviceInfoService = deviceInfoService ?? DeviceInfoService() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Load or generate keys
      await _loadKeys();

      // Initialize encrypters
      _initializeEncrypters();

      // Schedule key rotation if needed
      _scheduleKeyRotation();

      debugPrint('EncryptionService: Initialized successfully');
    } catch (e, stack) {
      debugPrint('EncryptionService: Error initializing: $e');
      debugPrint(stack.toString());

      // Emergency key generation
      await _generateNewKeys(emergency: true);
      _initializeEncrypters();
    }
  }

  Future<void> _loadKeys() async {
    try {
      // Try to load existing keys
      final primaryKeyStr = await _secureStorage.read(key: KEY_PRIMARY);
      final secondaryKeyStr = await _secureStorage.read(key: KEY_SECONDARY);
      final ivStr = await _secureStorage.read(key: KEY_IV);
      final lastRotationStr = await _secureStorage.read(key: KEY_LAST_ROTATION);

      if (primaryKeyStr != null && secondaryKeyStr != null && ivStr != null) {
        // Decrypt the stored keys
        final deviceId = await _deviceInfoService.getOrCreateUniqueDeviceId();
        final primaryKeyDecrypted = _decryptStoredKey(primaryKeyStr, deviceId);
        final secondaryKeyDecrypted =
            _decryptStoredKey(secondaryKeyStr, deviceId);
        final ivDecrypted = _decryptStoredKey(ivStr, deviceId);

        // Create keys from decrypted data
        _primaryKey = encrypt.Key(base64.decode(primaryKeyDecrypted));
        _secondaryKey = encrypt.Key(base64.decode(secondaryKeyDecrypted));
        _primaryIV = encrypt.IV(base64.decode(ivDecrypted));

        // Parse last rotation time
        if (lastRotationStr != null) {
          _lastKeyRotation = DateTime.parse(lastRotationStr);
        } else {
          _lastKeyRotation = DateTime.now();
          await _secureStorage.write(
            key: KEY_LAST_ROTATION,
            value: _lastKeyRotation!.toIso8601String(),
          );
        }

        debugPrint('EncryptionService: Loaded existing keys');
      } else {
        // Generate new keys if not found
        await _generateNewKeys();
      }
    } catch (e) {
      debugPrint('EncryptionService: Error loading keys: $e');
      // Generate new keys if loading fails
      await _generateNewKeys();
    }
  }

  Future<void> _generateNewKeys({bool emergency = false}) async {
    debugPrint('EncryptionService: Generating new encryption keys');

    try {
      // Generate random keys
      final primaryKeyBytes = _generateSecureRandomBytes(32); // 256 bits
      final secondaryKeyBytes = _generateSecureRandomBytes(32); // 256 bits
      final ivBytes = _generateSecureRandomBytes(16); // 128 bits

      // Create keys
      _primaryKey = encrypt.Key(Uint8List.fromList(primaryKeyBytes));
      _secondaryKey = encrypt.Key(Uint8List.fromList(secondaryKeyBytes));
      _primaryIV = encrypt.IV(Uint8List.fromList(ivBytes));

      // Update last rotation time
      _lastKeyRotation = DateTime.now();

      // Store keys securely
      if (!emergency) {
        await _saveKeys();
      }
    } catch (e) {
      debugPrint('EncryptionService: Error generating new keys: $e');
      throw Exception('Failed to generate encryption keys: $e');
    }
  }

  Future<void> _saveKeys() async {
    try {
      // Get device ID for key wrapping
      final deviceId = await _deviceInfoService.getOrCreateUniqueDeviceId();

      // Encrypt keys before storing
      final primaryKeyEncrypted =
          _encryptKeyForStorage(base64.encode(_primaryKey.bytes), deviceId);
      final secondaryKeyEncrypted =
          _encryptKeyForStorage(base64.encode(_secondaryKey.bytes), deviceId);
      final ivEncrypted =
          _encryptKeyForStorage(base64.encode(_primaryIV.bytes), deviceId);

      // Store encrypted keys
      await _secureStorage.write(key: KEY_PRIMARY, value: primaryKeyEncrypted);
      await _secureStorage.write(
          key: KEY_SECONDARY, value: secondaryKeyEncrypted);
      await _secureStorage.write(key: KEY_IV, value: ivEncrypted);

      // Store last rotation time
      await _secureStorage.write(
          key: KEY_LAST_ROTATION, value: _lastKeyRotation!.toIso8601String());

      debugPrint('EncryptionService: Keys saved securely');
    } catch (e) {
      debugPrint('EncryptionService: Error saving keys: $e');
      throw Exception('Failed to save encryption keys: $e');
    }
  }

  void _initializeEncrypters() {
    // Initialize AES encrypter with CBC mode
    _aesEncrypter =
        encrypt.Encrypter(encrypt.AES(_primaryKey, mode: encrypt.AESMode.cbc));

    // Initialize Salsa20 encrypter as secondary algorithm
    _salsa20Encrypter = encrypt.Encrypter(encrypt.Salsa20(_secondaryKey));

    debugPrint('EncryptionService: Encrypters initialized');
  }

  void _scheduleKeyRotation() {
    // Determine when next key rotation should occur
    if (_lastKeyRotation != null) {
      final daysSinceRotation =
          DateTime.now().difference(_lastKeyRotation!).inDays;

      // Rotate keys every 7 days
      if (daysSinceRotation >= 7) {
        // Schedule key rotation
        Future.delayed(const Duration(minutes: 5), () {
          _rotateKeys();
        });
      }
    }
  }

  Future<void> _rotateKeys() async {
    try {
      debugPrint('EncryptionService: Rotating encryption keys');

      // Keep old primary key as secondary
      final oldPrimaryKey = _primaryKey;

      // Generate new primary key
      final newPrimaryKeyBytes = _generateSecureRandomBytes(32);
      _primaryKey = encrypt.Key(Uint8List.fromList(newPrimaryKeyBytes));

      // Update secondary key
      _secondaryKey = oldPrimaryKey;

      // Generate new IV
      final newIVBytes = _generateSecureRandomBytes(16);
      _primaryIV = encrypt.IV(Uint8List.fromList(newIVBytes));

      // Update last rotation time
      _lastKeyRotation = DateTime.now();

      // Re-initialize encrypters with new keys
      _initializeEncrypters();

      // Save new keys
      await _saveKeys();

      debugPrint('EncryptionService: Key rotation completed');
    } catch (e) {
      debugPrint('EncryptionService: Error rotating keys: $e');
    }
  }

  // UTILITY METHODS

  List<int> _generateSecureRandomBytes(int length) {
    final bytes = List<int>.generate(length, (_) => _random.nextInt(256));
    return bytes;
  }

  String _encryptKeyForStorage(String keyData, String deviceId) {
    // Create a device-specific wrapping key
    final wrappingKeyMaterial = utf8.encode(deviceId + ':encryption_wrapper');
    final wrappingKey = sha256.convert(wrappingKeyMaterial).bytes;

    // Use first 16 bytes as IV
    final iv = wrappingKey.sublist(0, 16);

    // Use remaining bytes as key
    final key = encrypt.Key(Uint8List.fromList(wrappingKey.sublist(16)));

    // Create encrypter
    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    // Encrypt
    final encrypted =
        encrypter.encrypt(keyData, iv: encrypt.IV(Uint8List.fromList(iv)));

    return encrypted.base64;
  }

  String _decryptStoredKey(String encryptedKey, String deviceId) {
    // Recreate the same wrapping key
    final wrappingKeyMaterial = utf8.encode(deviceId + ':encryption_wrapper');
    final wrappingKey = sha256.convert(wrappingKeyMaterial).bytes;

    // Use first 16 bytes as IV
    final iv = wrappingKey.sublist(0, 16);

    // Use remaining bytes as key
    final key = encrypt.Key(Uint8List.fromList(wrappingKey.sublist(16)));

    // Create encrypter
    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    // Decrypt
    final decrypted = encrypter.decrypt64(encryptedKey,
        iv: encrypt.IV(Uint8List.fromList(iv)));

    return decrypted;
  }

  // PUBLIC API

  /// Encrypt data using primary algorithm (AES-256-CBC)
  String encryptText(String plainText) {
    try {
      // Generate a random IV for each encryption
      final iv = encrypt.IV.fromSecureRandom(16);

      // Encrypt
      final encrypted = _aesEncrypter.encrypt(plainText, iv: iv);

      // Combine IV and encrypted data
      return '${base64.encode(iv.bytes)}:${encrypted.base64}';
    } catch (e) {
      debugPrint('EncryptionService: Error encrypting text: $e');
      throw Exception('Encryption failed: $e');
    }
  }

  /// Decrypt data encrypted with encryptText
  String decryptText(String encryptedText) {
    try {
      // Split IV and encrypted data
      final parts = encryptedText.split(':');
      if (parts.length != 2) {
        throw FormatException('Invalid encrypted text format');
      }

      // Extract IV
      final iv = encrypt.IV(base64.decode(parts[0]));

      // Decrypt
      final decrypted = _aesEncrypter.decrypt64(parts[1], iv: iv);

      return decrypted;
    } catch (e) {
      debugPrint('EncryptionService: Error decrypting text: $e');
      throw Exception('Decryption failed: $e');
    }
  }

  /// Encrypt data with double encryption (AES + Salsa20)
  String encryptSecure(String plainText) {
    try {
      // First layer: Salsa20
      final iv1 = encrypt.IV.fromSecureRandom(8);
      final firstLayer = _salsa20Encrypter.encrypt(plainText, iv: iv1);

      // Second layer: AES-256-CBC
      final iv2 = encrypt.IV.fromSecureRandom(16);
      final secondLayer = _aesEncrypter.encrypt(firstLayer.base64, iv: iv2);

      // Combine IVs and encrypted data
      return '${base64.encode(iv1.bytes)}:${base64.encode(iv2.bytes)}:${secondLayer.base64}';
    } catch (e) {
      debugPrint('EncryptionService: Error secure encrypting text: $e');
      throw Exception('Secure encryption failed: $e');
    }
  }

  /// Decrypt data encrypted with encryptSecure
  String decryptSecure(String encryptedText) {
    try {
      // Split IVs and encrypted data
      final parts = encryptedText.split(':');
      if (parts.length != 3) {
        throw FormatException('Invalid secure encrypted text format');
      }

      // Extract IVs
      final iv1 = encrypt.IV(base64.decode(parts[0]));
      final iv2 = encrypt.IV(base64.decode(parts[1]));

      // Decrypt second layer (AES)
      final secondLayerDecrypted = _aesEncrypter.decrypt64(parts[2], iv: iv2);

      // Decrypt first layer (Salsa20)
      final firstLayerDecrypted =
          _salsa20Encrypter.decrypt64(secondLayerDecrypted, iv: iv1);

      return firstLayerDecrypted;
    } catch (e) {
      debugPrint('EncryptionService: Error secure decrypting text: $e');
      throw Exception('Secure decryption failed: $e');
    }
  }

  /// Encrypt with obfuscation for network transmission
  String encryptForTransmission(String plainText) {
    try {
      // Add timestamp and random data
      final now = DateTime.now();
      final formattedDate = DateFormat('yyyyMMddHHmmss').format(now);
      final nonce = base64.encode(_generateSecureRandomBytes(8));

      // Prepare data with metadata
      final dataWithMeta = jsonEncode({
        'data': plainText,
        'timestamp': formattedDate,
        'nonce': nonce,
      });

      // Encrypt with AES
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypted = _aesEncrypter.encrypt(dataWithMeta, iv: iv);

      // Obfuscate
      final obfuscated =
          _obfuscateData('${base64.encode(iv.bytes)}:${encrypted.base64}');

      return obfuscated;
    } catch (e) {
      debugPrint('EncryptionService: Error encrypting for transmission: $e');
      throw Exception('Transmission encryption failed: $e');
    }
  }

  /// Decrypt and deobfuscate network transmission data
  String decryptFromTransmission(String obfuscatedText) {
    try {
      // Deobfuscate
      final deobfuscated = _deobfuscateData(obfuscatedText);

      // Split IV and encrypted data
      final parts = deobfuscated.split(':');
      if (parts.length != 2) {
        throw FormatException('Invalid transmission format');
      }

      // Extract IV
      final iv = encrypt.IV(base64.decode(parts[0]));

      // Decrypt AES layer
      final decrypted = _aesEncrypter.decrypt64(parts[1], iv: iv);

      // Parse JSON
      final jsonData = jsonDecode(decrypted);

      // Extract original data
      return jsonData['data'] as String;
    } catch (e) {
      debugPrint('EncryptionService: Error decrypting from transmission: $e');
      throw Exception('Transmission decryption failed: $e');
    }
  }

  /// Obfuscate data to make it look like normal text
  String _obfuscateData(String data) {
    // Convert to bytes
    final bytes = utf8.encode(data);

    // Simple XOR with a repeating key
    final key = utf8.encode('TheConduit');
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = bytes[i] ^ key[i % key.length];
    }

    // Convert to Base64 to make it look harmless
    final base64Data = base64.encode(bytes);

    // Add fake headers to make it look like a regular message
    return 'MSG-${DateTime.now().millisecondsSinceEpoch}:$base64Data';
  }

  /// Deobfuscate data
  String _deobfuscateData(String obfuscatedData) {
    // Remove fake headers
    final dataWithoutHeader = obfuscatedData.split(':').sublist(1).join(':');

    // Decode Base64
    final bytes = base64.decode(dataWithoutHeader);

    // Simple XOR with the same repeating key
    final key = utf8.encode('TheConduit');
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = bytes[i] ^ key[i % key.length];
    }

    // Convert back to string
    return utf8.decode(bytes);
  }

  /// Hash data securely (for verification, not for passwords)
  String hashData(String data) {
    // Add salt
    final salt = base64.encode(_generateSecureRandomBytes(16));
    final saltedData = data + salt;

    // Double hash
    final firstHash = sha256.convert(utf8.encode(saltedData));
    final secondHash = sha256.convert(firstHash.bytes);

    // Return hash with salt
    return '${secondHash.toString()}:$salt';
  }

  /// Verify hashed data
  bool verifyHash(String originalData, String hash) {
    try {
      // Split hash and salt
      final parts = hash.split(':');
      if (parts.length != 2) {
        return false;
      }

      final expectedHash = parts[0];
      final salt = parts[1];

      // Add salt to original data
      final saltedData = originalData + salt;

      // Double hash
      final firstHash = sha256.convert(utf8.encode(saltedData));
      final secondHash = sha256.convert(firstHash.bytes);

      // Compare
      return secondHash.toString() == expectedHash;
    } catch (e) {
      debugPrint('EncryptionService: Error verifying hash: $e');
      return false;
    }
  }

  /// Encrypt file data
  Future<Uint8List> encryptFile(Uint8List fileData) async {
    try {
      // Generate random IV
      final iv = encrypt.IV.fromSecureRandom(16);

      // Encrypt data
      final encrypter = encrypt.Encrypter(
          encrypt.AES(_primaryKey, mode: encrypt.AESMode.cbc));
      final encrypted = encrypter.encryptBytes(fileData, iv: iv);

      // Combine IV and encrypted data
      final result = BytesBuilder();
      result.add(iv.bytes);
      result.add(encrypted.bytes);

      return result.toBytes();
    } catch (e) {
      debugPrint('EncryptionService: Error encrypting file: $e');
      throw Exception('File encryption failed: $e');
    }
  }

  /// Decrypt file data
  Future<Uint8List> decryptFile(Uint8List encryptedData) async {
    try {
      // First 16 bytes should be the IV
      if (encryptedData.length <= 16) {
        throw FormatException('Invalid encrypted file format');
      }

      final iv = encrypt.IV(encryptedData.sublist(0, 16));
      final encryptedBytes = encryptedData.sublist(16);

      // Decrypt data
      final encrypter = encrypt.Encrypter(
          encrypt.AES(_primaryKey, mode: encrypt.AESMode.cbc));
      final decrypted =
          encrypter.decryptBytes(encrypt.Encrypted(encryptedBytes), iv: iv);

      return Uint8List.fromList(decrypted);
    } catch (e) {
      debugPrint('EncryptionService: Error decrypting file: $e');
      throw Exception('File decryption failed: $e');
    }
  }
}
