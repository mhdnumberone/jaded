// lib/presentation/permission_control/permission_control_screen.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../permissions/permission_service.dart';


class PermissionControlScreen extends StatefulWidget {
  final Widget Function(BuildContext) destinationBuilder;
  
  const PermissionControlScreen({
    super.key, 
    required this.destinationBuilder
  });

  @override
  State<PermissionControlScreen> createState() => _PermissionControlScreenState();
}

class _PermissionControlScreenState extends State<PermissionControlScreen> {
  final PermissionService _permissionService = PermissionService();
  
  bool _hasPermissions = false;
  bool _isLoadingPermissions = true;

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
  }

  Future<void> _checkAndRequestPermissions() async {
    if (!mounted) return;
    setState(() => _isLoadingPermissions = true);

    bool granted = await _permissionService.checkPermissions();
    if (!granted && mounted) {
      granted = await _permissionService.requestRequiredPermissions(context);
    }

    if (!mounted) return;
    setState(() {
      _hasPermissions = granted;
      _isLoadingPermissions = false;
    });

    if (granted) {
      // إذا تم منح جميع الأذونات، يمكننا الانتقال إلى الشاشة الرئيسية
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: widget.destinationBuilder),
          );
        });
      }
    } else {
      debugPrint("Permissions not granted. Cannot proceed to main app.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "بعض الأذونات مطلوبة لاستخدام ميزات الدردشة المتقدمة. يرجى منح الأذونات المطلوبة.",
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تطبيق الدردشة'),
        actions: [
          if (!_isLoadingPermissions && !_hasPermissions)
            IconButton(
              icon: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orangeAccent,
              ),
              tooltip: 'الأذونات مطلوبة',
              onPressed: _checkAndRequestPermissions,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoadingPermissions) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'جاري إعداد تطبيق الدردشة...',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (!_hasPermissions) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                color: Colors.blue.shade300,
                size: 70,
              ),
              const SizedBox(height: 20),
              const Text(
                'مرحباً بك في تطبيق الدردشة',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              Text(
                'لاستخدام جميع ميزات التطبيق، نحتاج إلى بعض الأذونات مثل الميكروفون والتخزين للرسائل الصوتية والصور.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 15),
              ),
              const SizedBox(height: 25),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('منح الأذونات والمتابعة'),
                onPressed: _checkAndRequestPermissions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                child: const Text(
                  'إعدادات التطبيق',
                  style: TextStyle(color: Colors.blue),
                ),
                onPressed: () => openAppSettings(),
              ),
            ],
          ),
        ),
      );
    }

    // إذا تم منح الأذونات، يجب أن نكون قد انتقلنا بالفعل إلى الشاشة الرئيسية
    // ولكن نعرض شاشة تحميل كاحتياط
    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}
