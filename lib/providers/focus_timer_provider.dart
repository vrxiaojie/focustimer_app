import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/focus_record.dart';
import '../services/ble_service.dart';

class FocusTimerProvider extends ChangeNotifier {
  final BleService _bleService = BleService();

  BleConnectionState get connectionState => _bleService.connectionState;
  BluetoothDevice? get connectedDevice => _bleService.device;

  TodayData? _todayData;
  TodayData? get todayData => _todayData;

  List<FocusRecord> _historyRecords = [];
  List<FocusRecord> get historyRecords => _historyRecords;

  Map<String, dynamic>? _powerSettingsPayload;
  Map<String, dynamic>? get powerSettingsPayload => _powerSettingsPayload == null
      ? null
      : Map<String, dynamic>.unmodifiable(_powerSettingsPayload!);

  List<ScanResult> _scanResults = [];
  List<ScanResult> get scanResults => _scanResults;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _deviceConnSub;
  Timer? _scanUiTimer;
  Timer? _scanTimeoutTimer;
  final Map<String, ScanResult> _scanMap = {};

  bool _autoReconnectRunning = false;
  bool get isAutoReconnectRunning => _autoReconnectRunning;

  String? _lastDeviceId;
  bool get canReconnect => (_lastDeviceId ?? '').isNotEmpty;

  FocusTimerProvider() {
    _loadCachedData();
  }

  @override
  void dispose() {
    stopScan();
    _deviceConnSub?.cancel();
    _deviceConnSub = null;
    super.dispose();
  }

  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedHistory = prefs.getString('cached_history');
      _lastDeviceId = prefs.getString('last_device_id');
      if (cachedHistory != null) {
        final jsonMap = jsonDecode(cachedHistory) as Map<String, dynamic>;
        _historyRecords = (jsonMap['records'] as List<dynamic>)
            .map((r) => FocusRecord.fromJson(r as Map<String, dynamic>))
            .toList();

        // Use today's record from history as cache for "今日专注".
        _todayData ??= _todayFromHistory(_historyRecords);
        notifyListeners();
      }
    } catch (_) {}

    // After cache is loaded, try auto-reconnect in background.
    unawaited(_tryAutoReconnect());
  }

  Future<void> _cacheHistoryData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonMap = {
        'records': _historyRecords.map((r) => r.toJson()).toList(),
      };
      await prefs.setString('cached_history', jsonEncode(jsonMap));
    } catch (_) {}
  }

  Future<void> startScan() async {
    // Restart scanning session
    stopScan();

    _isScanning = true;
    _scanResults = [];
    _scanMap.clear();
    _errorMessage = null;
    notifyListeners();

    // Request permissions first (required on Android 12+)
    final granted = await _bleService.requestPermissions();
    if (!granted) {
      _errorMessage = '蓝牙/定位权限未授予';
      _isScanning = false;
      notifyListeners();
      return;
    }

    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        throw Exception('设备不支持蓝牙');
      }
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        throw Exception('请先打开手机蓝牙');
      }

      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (!_isFocusTimerDevice(r)) continue;
          final id = r.device.remoteId.str;
          final existing = _scanMap[id];
          if (existing == null || r.rssi > existing.rssi) {
            _scanMap[id] = r;
          }
        }
      });

      _scanUiTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!_isScanning) return;
        final sorted = _scanMap.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
        _scanResults = sorted;
        notifyListeners();
      });

      _scanTimeoutTimer = Timer(const Duration(seconds: 20), () {
        stopScan();
      });

      await FlutterBluePlus.startScan();
    } catch (e) {
      _errorMessage = '扫描失败: $e';
      stopScan();
    }
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanSub = null;
    _scanUiTimer?.cancel();
    _scanUiTimer = null;
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;

    if (_isScanning) {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    // Connecting while scanning is allowed, but stopping scan improves reliability.
    stopScan();

    _errorMessage = null;
    notifyListeners();

    final success = await _bleService.connectToDevice(device);
    if (success) {
      await _saveLastConnectedDeviceId(device.remoteId.str);

      // Listen for remote disconnect and reflect it in UI.
      await _deviceConnSub?.cancel();
      _deviceConnSub = device.connectionState.listen((state) async {
        if (state == BluetoothConnectionState.disconnected) {
          _errorMessage = '设备已断开';
          try {
            await _bleService.disconnect();
          } catch (_) {}
          await _deviceConnSub?.cancel();
          _deviceConnSub = null;
          notifyListeners();
        }
      });

      notifyListeners();
      // Auto sync device settings and data after connection.
      await _readPowerSettingsAfterConnect();
      await syncData();
    } else {
      _errorMessage = '连接失败';
    }
    notifyListeners();
    return success;
  }

  Future<void> disconnect() async {
    await _deviceConnSub?.cancel();
    _deviceConnSub = null;
    await _bleService.disconnect();
    // Keep cached todayData on disconnect.
    notifyListeners();
  }

  Future<void> syncData() async {
    // Fallback first: use today's record from cached history
    _todayData ??= _todayFromHistory(_historyRecords);

    final todayData = await _bleService.readTodayData();
    final historyData = await _bleService.readHistoryData();

    if (historyData.isNotEmpty) {
      _historyRecords = historyData;
      await _cacheHistoryData();
    }

    final todayFromHistory = _todayFromHistory(_historyRecords);
    if (todayData != null) {
      _todayData = todayData;
    } else if (todayFromHistory != null) {
      _todayData = todayFromHistory;
    }

    notifyListeners();
  }

  Future<void> syncDeviceTimeUtc8() async {
    if (connectionState != BleConnectionState.connected) {
      throw Exception('请先连接设备');
    }

    final utc8Now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final payload = {
      'date': {
        'year': utc8Now.year,
        'month': utc8Now.month,
        'day': utc8Now.day,
      },
      'time': {
        'hour': utc8Now.hour,
        'minute': utc8Now.minute,
        'second': utc8Now.second,
      },
      'weekday': {
        // Dart weekday: Mon=1..Sun=7, device expects Sun=0..Sat=6
        'index': utc8Now.weekday % 7,
      },
    };

    await _bleService.writeDeviceTimePayload(payload);
  }

  Future<Map<String, dynamic>> readPowerSettings() async {
    if (connectionState != BleConnectionState.connected) {
      throw Exception('请先连接设备');
    }
    final payload = await _bleService.readPowerSettingsPayload();
    _powerSettingsPayload = Map<String, dynamic>.from(payload);
    notifyListeners();
    return Map<String, dynamic>.unmodifiable(_powerSettingsPayload!);
  }

  Future<void> writePowerSettings(Map<String, dynamic> payload) async {
    if (connectionState != BleConnectionState.connected) {
      throw Exception('请先连接设备');
    }
    await _bleService.writePowerSettingsPayload(payload);
    _powerSettingsPayload = Map<String, dynamic>.from(payload);
    notifyListeners();
  }

  Future<void> _readPowerSettingsAfterConnect() async {
    try {
      await readPowerSettings();
    } catch (_) {
      // Keep the device connected even if settings are unavailable or unreadable.
    }
  }

  Future<void> _saveLastConnectedDeviceId(String id) async {
    try {
      _lastDeviceId = id;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_device_id', id);
    } catch (_) {}
  }

  Future<String?> _getLastConnectedDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastDeviceId = prefs.getString('last_device_id');
      return _lastDeviceId;
    } catch (_) {
      return null;
    }
  }

  Future<void> reconnectLastDevice(
      {Duration timeout = const Duration(seconds: 8)}) async {
    if (connectionState == BleConnectionState.connecting) return;
    final lastId = _lastDeviceId ?? await _getLastConnectedDeviceId();
    if (lastId == null || lastId.isEmpty) {
      _errorMessage = '没有可重连的设备';
      notifyListeners();
      return;
    }

    _errorMessage = null;
    notifyListeners();

    // Ensure permissions
    final granted = await _bleService.requestPermissions();
    if (!granted) {
      _errorMessage = '蓝牙/定位权限未授予';
      notifyListeners();
      return;
    }

    StreamSubscription<List<ScanResult>>? sub;
    Timer? timer;
    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) throw Exception('设备不支持蓝牙');
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) throw Exception('请先打开手机蓝牙');

      FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan();

      final completer = Completer<void>();
      sub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          if (r.device.remoteId.str == lastId) {
            FlutterBluePlus.stopScan();
            await sub?.cancel();
            timer?.cancel();
            await connectToDevice(r.device);
            if (!completer.isCompleted) completer.complete();
            return;
          }
        }
      });

      timer = Timer(timeout, () async {
        FlutterBluePlus.stopScan();
        await sub?.cancel();
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future;
      if (connectionState != BleConnectionState.connected) {
        _errorMessage = '未找到上次设备';
        notifyListeners();
      }
    } catch (e) {
      FlutterBluePlus.stopScan();
      await sub?.cancel();
      timer?.cancel();
      _errorMessage = '重连失败: $e';
      notifyListeners();
    }
  }

  Future<void> _tryAutoReconnect() async {
    if (_autoReconnectRunning) return;
    if (connectionState == BleConnectionState.connected ||
        connectionState == BleConnectionState.connecting) {
      return;
    }

    final lastId = await _getLastConnectedDeviceId();
    if (lastId == null || lastId.isEmpty) return;

    // Avoid popping permission dialogs on startup if permissions are not granted yet.
    final scanStatus = await Permission.bluetoothScan.status;
    final connectStatus = await Permission.bluetoothConnect.status;
    final locationStatus = await Permission.locationWhenInUse.status;
    final hasPerms = (scanStatus.isGranted && connectStatus.isGranted) ||
        locationStatus.isGranted;
    if (!hasPerms) return;

    final supported = await FlutterBluePlus.isSupported;
    if (!supported) return;
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) return;

    _autoReconnectRunning = true;
    StreamSubscription<List<ScanResult>>? sub;
    Timer? timeout;
    try {
      FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan();

      final completer = Completer<void>();
      sub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          if (r.device.remoteId.str == lastId) {
            FlutterBluePlus.stopScan();
            await sub?.cancel();
            timeout?.cancel();
            await connectToDevice(r.device);
            completer.complete();
            return;
          }
        }
      });

      timeout = Timer(const Duration(seconds: 8), () async {
        FlutterBluePlus.stopScan();
        await sub?.cancel();
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future;
    } catch (_) {
      FlutterBluePlus.stopScan();
      await sub?.cancel();
      timeout?.cancel();
    } finally {
      _autoReconnectRunning = false;
    }
  }

  static TodayData? _todayFromHistory(List<FocusRecord> records) {
    final now = DateTime.now();
    final todayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final record = records.cast<FocusRecord?>().firstWhere(
          (r) => r?.date == todayKey,
          orElse: () => null,
        );
    if (record == null) return null;
    return TodayData(
      focusMinutes: record.focusMinutes,
      restMinutes: record.restMinutes,
      focusCount: record.focusCount,
      napCount: record.napCount,
    );
  }

  List<FocusRecord> getWeekRecords() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    return _historyRecords.where((r) {
      final date = DateTime.tryParse(r.date);
      if (date == null) return false;
      return date.isAfter(weekStart.subtract(const Duration(days: 1))) &&
          date.isBefore(now.add(const Duration(days: 1)));
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<FocusRecord> getMonthRecords() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    return _historyRecords.where((r) {
      final date = DateTime.tryParse(r.date);
      if (date == null) return false;
      return date.isAfter(monthStart.subtract(const Duration(days: 1))) &&
          date.isBefore(now.add(const Duration(days: 1)));
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  static bool _isFocusTimerDevice(ScanResult result) {
    final name = result.device.advName.isNotEmpty
        ? result.device.advName
        : result.device.platformName;
    return name == 'FocusTimer';
  }
}
