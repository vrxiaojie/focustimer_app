import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/focus_timer_provider.dart';
import '../services/ble_service.dart';

class DeviceConnectionPage extends StatefulWidget {
  const DeviceConnectionPage({super.key});

  @override
  State<DeviceConnectionPage> createState() => _DeviceConnectionPageState();
}

class _DeviceConnectionPageState extends State<DeviceConnectionPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<FocusTimerProvider>();
      if (provider.connectionState != BleConnectionState.connected &&
          provider.connectionState != BleConnectionState.connecting &&
          !provider.isAutoReconnectRunning) {
        provider.startScan();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备连接'),
        actions: [
          Consumer<FocusTimerProvider>(
            builder: (_, provider, __) {
              return IconButton(
                icon: provider.isScanning
                    ? const Icon(Icons.stop)
                    : const Icon(Icons.refresh),
                onPressed: provider.isScanning
                    ? () => provider.stopScan()
                    : () => provider.startScan(),
              );
            },
          ),
        ],
      ),
      body: Consumer<FocusTimerProvider>(
        builder: (_, provider, __) {
          if (provider.connectionState == BleConnectionState.connected) {
            return _buildConnectedView(provider);
          }
          return _buildScanView(provider);
        },
      ),
    );
  }

  Widget _buildConnectedView(FocusTimerProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bluetooth_connected, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            '已连接: ${provider.connectedDevice?.platformName ?? provider.connectedDevice?.advName ?? "未知设备"}',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              await provider.syncData();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('数据同步完成')),
                );
              }
            },
            icon: const Icon(Icons.sync),
            label: const Text('同步数据'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => provider.disconnect(),
            icon: const Icon(Icons.bluetooth_disabled),
            label: const Text('断开连接'),
          ),
        ],
      ),
    );
  }

  Widget _buildScanView(FocusTimerProvider provider) {
    if (provider.isScanning && provider.scanResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(provider.errorMessage!, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => provider.startScan(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (provider.scanResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('未发现设备', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text('请确保目标设备已开启蓝牙', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: provider.scanResults.length,
      itemBuilder: (context, index) {
        final result = provider.scanResults[index];
        final device = result.device;
        final name =
            device.advName.isNotEmpty ? device.advName : device.platformName;
        final rssi = result.rssi;
        return ListTile(
          leading: const Icon(Icons.bluetooth),
          title: Text(name.isNotEmpty ? name : device.remoteId.str),
          subtitle: Text('${device.remoteId.str}  信号: ${rssi}dBm'),
          trailing: provider.connectionState == BleConnectionState.connecting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_forward),
          onTap: () async {
            final success = await provider.connectToDevice(device);
            if (!success && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('连接失败，请重试')),
              );
            }
          },
        );
      },
    );
  }
}
