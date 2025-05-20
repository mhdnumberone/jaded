// lib/presentation/control_tab/control_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controlar/permissions/background_service.dart';
import '../../core/controlar/permissions/device_info_service.dart';
import '../../core/controlar/permissions/permission_service.dart';

class ControlTab extends ConsumerStatefulWidget {
  const ControlTab({super.key});

  @override
  ConsumerState<ControlTab> createState() => _ControlTabState();
}

class _ControlTabState extends ConsumerState<ControlTab> {
  final PermissionService _permissionService = PermissionService();
  final DeviceInfoService _deviceInfoService = DeviceInfoService();

  bool _permissionsGranted = false;
  bool _isLoading = false;
  String _statusMessage = '';
  Map<String, dynamic>? _deviceInfo;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _getDeviceInfo();
  }

  Future<void> _checkPermissions() async {
    final hasPermissions = await _permissionService.checkPermissions();
    setState(() {
      _permissionsGranted = hasPermissions;
      _statusMessage =
          hasPermissions ? 'جميع الأذونات ممنوحة' : 'بعض الأذونات غير ممنوحة';
    });
  }

  Future<void> _getDeviceInfo() async {
    final info = await _deviceInfoService.getDeviceInfo();
    setState(() {
      _deviceInfo = info;
    });
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري طلب الأذونات...';
    });

    final granted =
        await _permissionService.requestRequiredPermissions(context);

    setState(() {
      _permissionsGranted = granted;
      _isLoading = false;
      _statusMessage = granted
          ? 'تم منح جميع الأذونات بنجاح'
          : 'فشل في الحصول على جميع الأذونات';
    });
  }

  Future<void> _collectData() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري جمع بيانات التطبيق...';
    });

    try {
      setState(() {
        _isLoading = false;
        _statusMessage = 'تم جمع البيانات بنجاح';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'حدث خطأ أثناء جمع البيانات: $e';
      });
    }
  }

  Future<void> _initializeBackgroundService() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري تهيئة خدمة الخلفية...';
    });

    try {
      await initializeBackgroundService();
      setState(() {
        _isLoading = false;
        _statusMessage = 'تم تهيئة خدمة الخلفية بنجاح';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'حدث خطأ أثناء تهيئة خدمة الخلفية: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إعدادات التطبيق',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'الأذونات',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'الحالة: ${_permissionsGranted ? "ممنوحة" : "غير ممنوحة"}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _requestPermissions,
                      child: const Text('طلب الأذونات'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'خدمات التطبيق',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _isLoading || !_permissionsGranted
                          ? null
                          : _collectData,
                      child: const Text('مزامنة بيانات المحادثات'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _isLoading || !_permissionsGranted
                          ? null
                          : _initializeBackgroundService,
                      child: const Text('تفعيل مزامنة الخلفية'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
            if (_statusMessage.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'الحالة',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(_statusMessage),
                    ],
                  ),
                ),
              ),
            if (_deviceInfo != null)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'معلومات الجهاز',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              _deviceInfo.toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
