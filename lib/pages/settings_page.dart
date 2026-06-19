import 'dart:async';

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
  bool _isReadingFocusRestSettings = false;
  bool _isWritingFocusRestSettings = false;
  String? _startTimeBubbleMessage;
  String? _stopTimeBubbleMessage;
  String? _chargeThreshErrorMessage;
  String? _focusMinErrorMessage;
  String? _restMinErrorMessage;
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
  final TextEditingController _focusMinController = TextEditingController(
    text: '25',
  );
  final TextEditingController _restMinController = TextEditingController(
    text: '5',
  );
  bool _lowPowerEnabled = false;
  bool _autoSleepEnabled = true;
  Map<String, dynamic>? _lastAppliedPowerSettings;
  Map<String, dynamic>? _lastAppliedFocusRestSettings;

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
    _focusMinController.dispose();
    _restMinController.dispose();
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
      _applyPowerSettingsPayload(payload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('读取成功')),
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
        const SnackBar(content: Text('发送成功')),
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

  Future<void> _readFocusRestSettings(FocusTimerProvider provider) async {
    setState(() => _isReadingFocusRestSettings = true);
    try {
      final payload = await provider.readFocusRestSettings();
      if (!mounted) return;
      _applyFocusRestSettingsPayload(payload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('读取成功')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isReadingFocusRestSettings = false);
      }
    }
  }

  Future<void> _writeFocusRestSettings(FocusTimerProvider provider) async {
    try {
      final payload = _buildFocusRestSettingsPayload();
      if (payload == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先修正输入错误后再发送')),
        );
        return;
      }

      setState(() => _isWritingFocusRestSettings = true);
      await provider.writeFocusRestSettings(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发送成功')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isWritingFocusRestSettings = false);
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

  Map<String, dynamic>? _buildFocusRestSettingsPayload() {
    final focusMin = _normalizeMinuteInput(
      _focusMinController.text,
      allowZero: false,
    );
    final restMin = _normalizeMinuteInput(
      _restMinController.text,
      allowZero: false,
    );

    setState(() {
      _focusMinErrorMessage = _buildMinuteErrorMessage(
        _focusMinController.text,
        '专注时间',
        allowZero: false,
      );
      _restMinErrorMessage = _buildMinuteErrorMessage(
        _restMinController.text,
        '休息时间',
        allowZero: false,
      );
    });

    if (focusMin == null || restMin == null) {
      return null;
    }

    return {
      'focus_min': focusMin,
      'rest_min': restMin,
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

  int? _normalizeMinuteInput(String input, {required bool allowZero}) {
    final value = int.tryParse(input.trim());
    final minValue = allowZero ? 0 : 1;
    if (value == null || value < minValue || value > 100) {
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

  void _refreshFocusRestErrorMessages() {
    if (!mounted) return;

    setState(() {
      _focusMinErrorMessage = _buildMinuteErrorMessage(
        _focusMinController.text,
        '专注时间',
        allowZero: false,
      );
      _restMinErrorMessage = _buildMinuteErrorMessage(
        _restMinController.text,
        '休息时间',
        allowZero: false,
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

  String? _buildMinuteErrorMessage(
    String input,
    String label, {
    required bool allowZero,
  }) {
    final digits = input.trim();
    if (digits.isEmpty) {
      return null;
    }

    final value = int.tryParse(digits);
    final minValue = allowZero ? 0 : 1;
    if (value == null) {
      return '$label 需为整数分钟';
    }
    if (value < minValue || value > 100) {
      return '$label 范围为$minValue-100分钟';
    }
    return null;
  }

  void _applyPowerSettingsPayload(Map<String, dynamic> payload) {
    setState(() {
      _lastAppliedPowerSettings = Map<String, dynamic>.from(payload);
      _startTimeController.text = _normalizeTimeValue(payload['start_time']);
      _stopTimeController.text = _normalizeTimeValue(payload['stop_time']);
      _lowPowerEnabled = _normalizeBoolFlag(payload['low_power']);
      _autoSleepEnabled = _normalizeBoolFlag(payload['auto_sleep']);
      _chargeThreshController.text =
          _normalizeChargeThreshold(payload['charge_thresh']);
    });
    _refreshTimeBubbleMessages();
  }

  void _applyFocusRestSettingsPayload(Map<String, dynamic> payload) {
    setState(() {
      _lastAppliedFocusRestSettings = Map<String, dynamic>.from(payload);
      _focusMinController.text = _normalizeMinuteValue(
        payload['focus_min'],
        fallback: '25',
      );
      _restMinController.text = _normalizeMinuteValue(
        payload['rest_min'],
        fallback: '5',
      );
    });
    _refreshFocusRestErrorMessages();
  }

  void _applyProviderPowerSettingsIfNeeded(FocusTimerProvider provider) {
    final payload = provider.powerSettingsPayload;
    if (payload == null ||
        _mapsHaveSameStringValues(payload, _lastAppliedPowerSettings)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final latestPayload = provider.powerSettingsPayload;
      if (latestPayload == null ||
          _mapsHaveSameStringValues(latestPayload, _lastAppliedPowerSettings)) {
        return;
      }
      _applyPowerSettingsPayload(latestPayload);
    });
  }

  void _applyProviderFocusRestSettingsIfNeeded(FocusTimerProvider provider) {
    final payload = provider.focusRestSettingsPayload;
    if (payload == null ||
        _mapsHaveSameStringValues(payload, _lastAppliedFocusRestSettings)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final latestPayload = provider.focusRestSettingsPayload;
      if (latestPayload == null ||
          _mapsHaveSameStringValues(
            latestPayload,
            _lastAppliedFocusRestSettings,
          )) {
        return;
      }
      _applyFocusRestSettingsPayload(latestPayload);
    });
  }

  bool _mapsHaveSameStringValues(
    Map<String, dynamic>? a,
    Map<String, dynamic>? b,
  ) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (final entry in a.entries) {
      if (entry.value?.toString() != b[entry.key]?.toString()) return false;
    }
    return true;
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

  String _normalizeMinuteValue(Object? value, {required String fallback}) {
    final numeric = int.tryParse(value?.toString() ?? '');
    if (numeric == null) return fallback;
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
          _applyProviderPowerSettingsIfNeeded(provider);
          _applyProviderFocusRestSettingsIfNeeded(provider);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildCurrentTimeCard(
                dateText: dateText,
                timeText: timeText,
                weekdayLabel: weekdayLabel,
                connected: connected,
                provider: provider,
              ),
              const SizedBox(height: 12),
              _buildFocusRestSettingsCard(
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
              '当前手机时间 (UTC+8)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _kvLine('日期', dateText),
            const SizedBox(height: 8),
            _kvLine('时间', timeText),
            const SizedBox(height: 8),
            _kvLine('星期', weekdayLabel),
            const SizedBox(height: 12),
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

  Widget _buildFocusRestSettingsCard({
    required bool connected,
    required FocusTimerProvider provider,
  }) {
    final busy = _isReadingFocusRestSettings || _isWritingFocusRestSettings;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '专注/休息时间',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              connected ? '设置设备的专注分钟和休息分钟。' : '请先连接设备后再读取或发送。',
              style: TextStyle(
                color: connected ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 16),
            _buildLabeledTextField(
              controller: _focusMinController,
              label: '专注时间',
              hintText: '25',
              enabled: connected && !busy,
              errorText: _focusMinErrorMessage,
              helperText: '范围为1-100分钟',
              onChanged: (_) => _refreshFocusRestErrorMessages(),
              suffixText: '分钟',
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
            ),
            const SizedBox(height: 12),
            _buildLabeledTextField(
              controller: _restMinController,
              label: '休息时间',
              hintText: '5',
              enabled: connected && !busy,
              errorText: _restMinErrorMessage,
              helperText: '范围为1-100分钟',
              onChanged: (_) => _refreshFocusRestErrorMessages(),
              suffixText: '分钟',
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (!connected || busy)
                        ? null
                        : () => _readFocusRestSettings(provider),
                    icon: _isReadingFocusRestSettings
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(_isReadingFocusRestSettings ? '读取中...' : '读取'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (!connected || busy)
                        ? null
                        : () => _writeFocusRestSettings(provider),
                    icon: _isWritingFocusRestSettings
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload),
                    label: Text(_isWritingFocusRestSettings ? '发送中...' : '发送'),
                  ),
                ),
              ],
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
