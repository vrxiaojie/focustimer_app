import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/focus_timer_provider.dart';
import '../services/ble_service.dart';
import 'device_connection_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('专注时钟'),
        actions: [
          Consumer<FocusTimerProvider>(
            builder: (_, provider, __) {
              return IconButton(
                icon: Icon(
                  provider.connectionState == BleConnectionState.connected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color:
                      provider.connectionState == BleConnectionState.connected
                          ? Colors.green
                          : Colors.grey,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DeviceConnectionPage()),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Consumer<FocusTimerProvider>(
        builder: (_, provider, __) {
          return RefreshIndicator(
            onRefresh: () => provider.syncData(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildConnectionStatus(provider),
                const SizedBox(height: 24),
                _buildTodayCard(provider),
                const SizedBox(height: 24),
                _buildHistoryList(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionStatus(FocusTimerProvider provider) {
    String statusText;
    Color statusColor;

    switch (provider.connectionState) {
      case BleConnectionState.connected:
        statusText = '已连接';
        statusColor = Colors.green;
        break;
      case BleConnectionState.connecting:
        statusText = '连接中...';
        statusColor = Colors.orange;
        break;
      case BleConnectionState.error:
        statusText = '连接错误';
        statusColor = Colors.red;
        break;
      case BleConnectionState.disconnected:
        statusText = '未连接';
        statusColor = Colors.grey;
        break;
    }

    return Card(
      child: ListTile(
        leading: Icon(Icons.bluetooth, color: statusColor),
        title: Text('蓝牙状态: $statusText'),
        trailing: TextButton(
          onPressed: () {},
          child: const Text('管理设备'),
        ),
      ),
    );
  }

  Widget _buildTodayCard(FocusTimerProvider provider) {
    final today = provider.todayData;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '今日专注',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _buildStatItem(
                  icon: Icons.timer,
                  label: '专注次数',
                  value: today?.focusCount.toString() ?? '--',
                  color: Colors.orange,
                ),
                _buildStatItem(
                  icon: Icons.coffee,
                  label: '休息次数',
                  value: today?.napCount.toString() ?? '--',
                  color: Colors.blue,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatItem(
                  icon: Icons.hourglass_empty,
                  label: '专注时长',
                  value: today != null ? '${today.focusMinutes}分钟' : '--',
                  color: Colors.deepOrange,
                ),
                _buildStatItem(
                  icon: Icons.weekend,
                  label: '休息时长',
                  value: today != null ? '${today.restMinutes}分钟' : '--',
                  color: Colors.lightBlue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(FocusTimerProvider provider) {
    if (provider.historyRecords.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.history, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text('暂无历史记录', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 4),
              Text('连接设备后同步数据',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '历史记录',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...provider.historyRecords.map((record) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.event_note),
                title: Text(record.date),
                subtitle: Text(
                  '专注${record.focusCount}次/${record.focusMinutes}分钟 | 休息${record.napCount}次/${record.restMinutes}分钟',
                ),
              ),
            )),
      ],
    );
  }
}
