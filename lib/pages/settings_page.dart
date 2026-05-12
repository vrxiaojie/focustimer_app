import 'dart:async';

import 'package:flutter/material.dart';
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
  late DateTime _currentUtc8;
  Timer? _clockTimer;

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
