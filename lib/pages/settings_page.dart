import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/focus_timer_provider.dart';
import '../services/ble_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isWriting = false;
  bool _isReadingPowerSettings = false;
  bool _isWritingPowerSettings = false;
  String? _startTimeBubbleMessage;
  String? _stopTimeBubbleMessage;
  String? _chargeThreshErrorMessage;
  late DateTime _currentUtc8;
  Timer? _clockTimer;
  final TextEditingController _startTimeController = TextEditingController(
    text: '2200',
  );
  final TextEditingController _stopTimeController = TextEditingController(
    text: '0600',
  );
  final TextEditingController _chargeThreshController = TextEditingController(
    text: '85',
  );
  bool _lowPowerEnabled = false;
  bool _autoSleepEnabled = true;

  DateTime get _utc8Now => DateTime.now().toUtc().add(const Duration(hours: 8));

  @override
  void initState() {
    super.initState();
    _currentUtc8 = _utc8Now;
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _currentUtc8 = _utc8Now;
      });
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _startTimeController.dispose();
    _stopTimeController.dispose();
    _chargeThreshController.dispose();
    super.dispose();
  }

  String _weekLabel(int index) {
    const labels = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
    return labels[index.clamp(0, 6)];
  }

  Future<void> _writeTime(FocusTimerProvider provider) async {
    setState(() => _isWriting = true);
    try {
      await provider.syncDeviceTimeUtc8();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('时间写入成功')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写入失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isWriting = false);
      }
    }
  }

  Future<void> _readPowerSettings(FocusTimerProvider provider) async {
    setState(() => _isReadingPowerSettings = true);
    try {
      final payload = await provider.readPowerSettings();
      if (!mounted) return;
      setState(() {
        _startTimeController.text = _normalizeTimeValue(payload['start_time']);
        _stopTimeController.text = _normalizeTimeValue(payload['stop_time']);
        _lowPowerEnabled = _normalizeBoolFlag(payload['low_power']);
        _autoSleepEnabled = _normalizeBoolFlag(payload['auto_sleep']);
        _chargeThreshController.text =
            _normalizeChargeThreshold(payload['charge_thresh']);
      });
      _refreshTimeBubbleMessages();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取成功')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isReadingPowerSettings = false);
      }
    }
  }

  Future<void> _writePowerSettings(FocusTimerProvider provider) async {
    try {
      final payload = _buildPowerSettingsPayload();
      if (payload == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先修正输入错误后再发送')),
        );
        return;
      }

      setState(() => _isWritingPowerSettings = true);
      await provider.writePowerSettings(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送成功')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isWritingPowerSettings = false);
      }
    }
  }

  Map<String, dynamic>? _buildPowerSettingsPayload() {
    final startTime = _normalizeTimeInput(_startTimeController.text, '关屏开始时间');
    final stopTime = _normalizeTimeInput(_stopTimeController.text, '关屏结束时间');
    final chargeThresh = _normalizeThresholdInput(_chargeThreshController.text);

    setState(() {
      _startTimeBubbleMessage = _buildTimeBubbleMessage(
        _startTimeController.text,
        '开始时间',
      );
      _stopTimeBubbleMessage = _buildTimeBubbleMessage(
        _stopTimeController.text,
        '结束时间',
      );
      _chargeThreshErrorMessage = _buildThresholdErrorMessage(
        _chargeThreshController.text,
      );
    });

    if (startTime == null || stopTime == null || chargeThresh == null) {
      return null;
    }

    return {
      'start_time': startTime,
      'stop_time': stopTime,
      'low_power': _lowPowerEnabled ? 1 : 0,
      'auto_sleep': _autoSleepEnabled ? 1 : 0,
      'charge_thresh': chargeThresh,
    };
  }

  String? _normalizeTimeInput(String input, String fieldLabel) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 4) {
      return null;
    }

    final hour = int.tryParse(digits.substring(0, 2));
    final minute = int.tryParse(digits.substring(2, 4));
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return digits;
  }

  int? _normalizeThresholdInput(String input) {
    final value = int.tryParse(input.trim());
    if (value == null || value < 75 || value > 95) {
      return null;
    }
    return value;
  }

  void _refreshTimeBubbleMessages() {
    if (!mounted) return;

    setState(() {
      _startTimeBubbleMessage = _buildTimeBubbleMessage(
        _startTimeController.text,
        '开始时间',
      );
      _stopTimeBubbleMessage = _buildTimeBubbleMessage(
        _stopTimeController.text,
        '结束时间',
      );
      _chargeThreshErrorMessage = _buildThresholdErrorMessage(
        _chargeThreshController.text,
      );
    });
  }

  String? _buildTimeBubbleMessage(String input, String label) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return null;
    }
    if (digits.length != 4) {
      return '$label 需输入4位数字，例如 2200';
    }

    final hour = int.tryParse(digits.substring(0, 2));
    final minute = int.tryParse(digits.substring(2, 4));
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return '$label 超出有效时间范围，请输入 0000-2359';
    }
    return null;
  }

  String? _buildThresholdErrorMessage(String input) {
    final digits = input.trim();
    if (digits.isEmpty) {
      return null;
    }

    final value = int.tryParse(digits);
    if (value == null) {
      return '充电阈值需为2位数字';
    }
    if (digits.length > 2) {
      return '充电阈值最多输入2位数字';
    }
    if (value < 75 || value > 95) {
      return '充电阈值范围为75-95';
    }
    return null;
  }

  String _normalizeTimeValue(Object? value) {
    final digits = value?.toString() ?? '';
    return digits.padLeft(4, '0');
  }

  bool _normalizeBoolFlag(Object? value) {
    if (value is bool) return value;
    return value?.toString() == '1';
  }

  String _normalizeChargeThreshold(Object? value) {
    final numeric = int.tryParse(value?.toString() ?? '');
    if (numeric == null) return '85';
    return numeric.toString();
  }

  @override
  Widget build(BuildContext context) {
    final now = _currentUtc8;
    final weekdayIndex = now.weekday % 7;
    final weekdayLabel = _weekLabel(weekdayIndex);

    final dateText =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final timeText =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Consumer<FocusTimerProvider>(
        builder: (_, provider, __) {
          final connected =
              provider.connectionState == BleConnectionState.connected;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildCurrentTimeCard(
                dateText: dateText,
                timeText: timeText,
                weekdayLabel: weekdayLabel,
              ),
              const SizedBox(height: 12),
              _buildWriteTimeCard(
                connected: connected,
                provider: provider,
              ),
              const SizedBox(height: 12),
              _buildPowerSettingsCard(
                connected: connected,
                provider: provider,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCurrentTimeCard({
    required String dateText,
    required String timeText,
    required String weekdayLabel,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '当前手机时间 (UTC+8)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _kvLine('日期', dateText),
            const SizedBox(height: 8),
            _kvLine('时间', timeText),
            const SizedBox(height: 8),
            _kvLine('星期', weekdayLabel),
          ],
        ),
      ),
    );
  }

  Widget _buildWriteTimeCard({
    required bool connected,
    required FocusTimerProvider provider,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '写入设备时间',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              connected ? '设备已连接，可写入时间。' : '请先连接设备后再写入时间。',
              style: TextStyle(
                color: connected ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (!connected || _isWriting)
                    ? null
                    : () => _writeTime(provider),
                icon: _isWriting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.schedule_send),
                label: Text(_isWriting ? '写入中...' : '写入当前时间到设备'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerSettingsCard({
    required bool connected,
    required FocusTimerProvider provider,
  }) {
    final busy = _isReadingPowerSettings || _isWritingPowerSettings;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '电源页面设置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              connected ? '时间设置2215代表22点15分' : '请先连接设备后再读取或发送。',
              style: TextStyle(
                color: connected ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 16),
            _buildLabeledTextField(
              controller: _startTimeController,
              label: '开始时间',
              hintText: '2200',
              enabled: connected && !busy,
              bubbleMessage: _startTimeBubbleMessage,
              onChanged: (_) => _refreshTimeBubbleMessages(),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
            ),
            const SizedBox(height: 12),
            _buildLabeledTextField(
              controller: _stopTimeController,
              label: '结束时间',
              hintText: '0600',
              enabled: connected && !busy,
              bubbleMessage: _stopTimeBubbleMessage,
              onChanged: (_) => _refreshTimeBubbleMessages(),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('低功耗模式'),
              value: _lowPowerEnabled,
              onChanged: connected && !busy
                  ? (value) => setState(() => _lowPowerEnabled = value)
                  : null,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动休眠'),
              value: _autoSleepEnabled,
              onChanged: connected && !busy
                  ? (value) => setState(() => _autoSleepEnabled = value)
                  : null,
            ),
            const SizedBox(height: 4),
            _buildLabeledTextField(
              controller: _chargeThreshController,
              label: '充电阈值',
              hintText: '85',
              enabled: connected && !busy,
              errorText: _chargeThreshErrorMessage,
              helperText: '范围为75-95',
              onChanged: (_) => _refreshTimeBubbleMessages(),
              suffixText: '%',
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (!connected || busy)
                        ? null
                        : () => _readPowerSettings(provider),
                    icon: _isReadingPowerSettings
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(_isReadingPowerSettings ? '读取中...' : '读取'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (!connected || busy)
                        ? null
                        : () => _writePowerSettings(provider),
                    icon: _isWritingPowerSettings
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload),
                    label: Text(_isWritingPowerSettings ? '发送中...' : '发送'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabeledTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required bool enabled,
    String? bubbleMessage,
    String? errorText,
    String? helperText,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
    String? suffixText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bubbleMessage != null) ...[
          _buildValidationBubble(bubbleMessage),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            hintText: hintText,
            errorText: errorText,
            helperText: helperText,
            border: const OutlineInputBorder(),
            suffixText: suffixText,
          ),
        ),
      ],
    );
  }

  Widget _buildValidationBubble(String message) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvLine(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
