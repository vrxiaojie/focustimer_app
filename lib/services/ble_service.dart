import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/focus_record.dart';

class BleConstants {
  static const String serviceUuid = "00000000-0000-0000-0000-0000-0000-FFF0";
  static const String charTodayUuid = "00000000-0000-0000-0000-0000-0000-0001";
  static const String charHistoryUuid =
      "00000000-0000-0000-0000-0000-0000-0002";
}

enum BleConnectionState { disconnected, connecting, connected, error }

class BleService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _charToday;
  BluetoothCharacteristic? _charHistory;

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  BleConnectionState get connectionState => _connectionState;

  BluetoothDevice? get device => _device;

  Stream<BluetoothConnectionState> get connectionStateStream {
    return _device?.connectionState ?? const Stream.empty();
  }

  Future<List<BluetoothDevice>> scanDevices(
      {Duration timeout = const Duration(seconds: 10)}) async {
    List<BluetoothDevice> foundDevices = [];
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      foundDevices = FlutterBluePlus.lastScanResults
          .map((r) => r.device)
          .where((d) => d.platformName.isNotEmpty || d.advName.isNotEmpty)
          .toList();
    } catch (e) {
      _connectionState = BleConnectionState.error;
    }
    return foundDevices;
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    _connectionState = BleConnectionState.connecting;
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      _device = device;
      _connectionState = BleConnectionState.connected;

      // Discover services
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) =>
            s.serviceUuid.str128.toLowerCase() ==
            BleConstants.serviceUuid.toLowerCase(),
        orElse: () => throw Exception('Service not found'),
      );

      for (final characteristic in service.characteristics) {
        final uuid = characteristic.characteristicUuid.str128.toLowerCase();
        if (uuid == BleConstants.charTodayUuid.toLowerCase()) {
          _charToday = characteristic;
        } else if (uuid == BleConstants.charHistoryUuid.toLowerCase()) {
          _charHistory = characteristic;
        }
      }

      return true;
    } catch (e) {
      _connectionState = BleConnectionState.error;
      _device = null;
      return false;
    }
  }

  Future<TodayData?> readTodayData() async {
    if (_charToday == null) return null;
    try {
      final data = await _charToday!.read();
      return TodayData.fromRawData(data);
    } catch (e) {
      return null;
    }
  }

  Future<List<FocusRecord>> readHistoryData() async {
    if (_charHistory == null) return [];
    try {
      final data = await _charHistory!.read();
      final jsonString = String.fromCharCodes(data);
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final records = (jsonMap['records'] as List<dynamic>)
          .map((r) => FocusRecord.fromJson(r as Map<String, dynamic>))
          .toList();
      return records;
    } catch (e) {
      return [];
    }
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _charToday = null;
    _charHistory = null;
    _connectionState = BleConnectionState.disconnected;
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
  }
}
