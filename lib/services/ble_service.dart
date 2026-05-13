import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/focus_record.dart';

class BleConstants {
  static const int preferredMtu = 512;
  static const String serviceUuid = "00000000-0000-0000-0000-0000-0000-FFF0";
  static const String charTodayUuid = "00000000-0000-0000-0000-0000-0000-0001";
  static const String charHistoryUuid =
      "00000000-0000-0000-0000-0000-0000-0002";
  static const String charTimeSyncUuid =
      "00000000-0000-0000-0000-0000-0000-0003";
  static const String charStartSendUuid =
      "00000000-0000-0000-0000-0000-0000-0004";
}

enum BleConnectionState { disconnected, connecting, connected, error }

class BleService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _charToday;
  BluetoothCharacteristic? _charHistory;
  BluetoothCharacteristic? _charTimeSync;
  BluetoothCharacteristic? _charStartSend;

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  BleConnectionState get connectionState => _connectionState;

  BluetoothDevice? get device => _device;

  Stream<BluetoothConnectionState> get connectionStateStream {
    return _device?.connectionState ?? const Stream.empty();
  }

  Future<bool> requestPermissions() async {
    try {
      final statuses = await <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
        Permission.location,
      ].request();

      final scan = statuses[Permission.bluetoothScan];
      final connect = statuses[Permission.bluetoothConnect];
      final location = statuses[Permission.locationWhenInUse] ??
          statuses[Permission.location];

      final scanGranted = scan?.isGranted ?? false;
      final connectGranted = connect?.isGranted ?? false;
      final locationGranted = location?.isGranted ?? false;

      // Android 12+ typically requires BLUETOOTH_SCAN/CONNECT.
      // Android 11- typically requires location permission (and location service on).
      if (scanGranted || connectGranted) {
        return scanGranted && connectGranted;
      }
      return locationGranted;
    } catch (_) {
      return false;
    }
  }

  Future<List<ScanResult>> scanDevices(
      {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        throw Exception('设备不支持蓝牙');
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        throw Exception('请先打开手机蓝牙');
      }

      // Stop any previous scan to avoid "already scanning" edge-cases.
      FlutterBluePlus.stopScan();

      // Collect results over time (reading lastScanResults immediately often returns empty).
      final Map<String, ScanResult> uniqueResults = {};
      final sub = FlutterBluePlus.scanResults.listen(
        (results) {
          for (final r in results) {
            final id = r.device.remoteId.str;
            final existing = uniqueResults[id];
            if (existing == null || r.rssi > existing.rssi) {
              uniqueResults[id] = r;
            }
          }
        },
      );

      try {
        await FlutterBluePlus.startScan();
        await Future.delayed(timeout);
      } finally {
        FlutterBluePlus.stopScan();
        await sub.cancel();
      }

      final foundResults = uniqueResults.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
      return foundResults;
    } catch (e) {
      _connectionState = BleConnectionState.error;
      rethrow;
    }
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    _connectionState = BleConnectionState.connecting;
    try {
      try {
        await device.connect(timeout: const Duration(seconds: 15));
      } catch (_) {
        // flutter_blue_plus may log/throw on "already connected"; treat as success
        final state = await device.connectionState.first;
        if (state != BluetoothConnectionState.connected) {
          rethrow;
        }
      }

      _device = device;
      _connectionState = BleConnectionState.connected;
      await _ensurePreferredMtu(device);

      // Discover services & bind characteristics if present.
      // IMPORTANT: absence/mismatch here should not be treated as "connection failed".
      _charToday = null;
      _charHistory = null;
      _charTimeSync = null;
      _charStartSend = null;
      try {
        final services = await device.discoverServices();
        final service = services.firstWhere(
          (s) => _uuidMatches(s.serviceUuid.str128, BleConstants.serviceUuid),
          orElse: () => services.isNotEmpty
              ? services.first
              : throw Exception('No services'),
        );

        for (final characteristic in service.characteristics) {
          final uuid = characteristic.characteristicUuid.str128;
          if (_uuidMatches(uuid, BleConstants.charTodayUuid)) {
            _charToday = characteristic;
          } else if (_uuidMatches(uuid, BleConstants.charHistoryUuid)) {
            _charHistory = characteristic;
          } else if (_uuidMatches(uuid, BleConstants.charTimeSyncUuid)) {
            _charTimeSync = characteristic;
          } else if (_uuidMatches(uuid, BleConstants.charStartSendUuid)) {
            _charStartSend = characteristic;
          }
        }
      } catch (_) {
        // Keep connected; reads will simply return null/empty until UUIDs are corrected.
      }

      return true;
    } catch (e) {
      _connectionState = BleConnectionState.error;
      _device = null;
      _charToday = null;
      _charHistory = null;
      _charTimeSync = null;
      _charStartSend = null;
      return false;
    }
  }

  static bool _uuidMatches(String actual, String expected) {
    final aHex = _normalizeHex(actual);
    final eHex = _normalizeHex(expected);
    if (aHex.isNotEmpty && aHex.length == eHex.length && aHex == eHex) {
      return true;
    }

    final a32 = _extract32FromUuid(actual);
    final e32 = _extract32FromUuid(expected);
    if (a32 != null && e32 != null && a32 == e32) {
      return true;
    }

    final a16 = _extract16FromUuid(actual);
    final e16 = _extract16FromUuid(expected);
    if (a16 != null && e16 != null && a16 == e16) {
      return true;
    }

    return false;
  }

  static String _normalizeHex(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
  }

  static String? _extract16FromUuid(String uuid) {
    final lower = uuid.toLowerCase();
    final m = RegExp(
      r'^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$',
    ).firstMatch(lower);
    if (m != null) return m.group(1);

    final hex = _normalizeHex(uuid);
    if (hex.length < 4) return null;
    return hex.substring(hex.length - 4);
  }

  static String? _extract32FromUuid(String uuid) {
    final lower = uuid.toLowerCase();
    final m = RegExp(
      r'^([0-9a-f]{8})-0000-1000-8000-00805f9b34fb$',
    ).firstMatch(lower);
    if (m != null) return m.group(1);

    final hex = _normalizeHex(uuid);
    if (hex.length < 8) return null;
    return hex.substring(hex.length - 8);
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
    if (_charHistory == null || _charStartSend == null) return [];

    try {
      final jsonString = await _readHistoryJsonFromFrames();
      return _parseHistoryRecords(jsonString);
    } catch (e) {
      _logHistoryDebug('History frame read failed: $e');
      return [];
    }
  }

  Future<String> _readHistoryJsonFromFrames() async {
    final historyCharacteristic = _charHistory;
    final startSendCharacteristic = _charStartSend;
    if (historyCharacteristic == null || startSendCharacteristic == null) {
      throw StateError('History characteristics are unavailable');
    }

    final completer = Completer<String>();
    final fragments = <int, String>{};
    int? totalFrames;
    late final StreamSubscription<List<int>> subscription;
    final framePattern = RegExp(r'^\((\d+)/(\d+)\)(.*)$', dotAll: true);

    subscription = historyCharacteristic.onValueReceived.listen(
      (data) {
        final frame = utf8.decode(data, allowMalformed: true);
        final match = framePattern.firstMatch(frame);
        if (match == null) {
          _logHistoryDebug('Ignored malformed frame: ${jsonEncode(frame)}');
          return;
        }

        final frameNo = int.parse(match.group(1)!);
        final frameCount = int.parse(match.group(2)!);
        final payload = match.group(3)!;

        if (frameNo < 1 || frameNo > frameCount || frameCount <= 0) {
          if (!completer.isCompleted) {
            completer.completeError(
              const FormatException('Invalid history frame index'),
            );
          }
          return;
        }

        totalFrames ??= frameCount;
        if (totalFrames != frameCount) {
          if (!completer.isCompleted) {
            completer.completeError(
              const FormatException('Inconsistent history frame count'),
            );
          }
          return;
        }

        fragments[frameNo] = payload;
        _logHistoryDebug(
          'Frame $frameNo/$frameCount received, payloadChars=${payload.length}, payload=${jsonEncode(payload)}',
        );

        if (fragments.length == totalFrames && !completer.isCompleted) {
          final orderedPayloads = <String>[];
          for (var index = 1; index <= totalFrames!; index++) {
            final fragment = fragments[index];
            if (fragment == null) {
              completer.completeError(
                const FormatException('Missing history frame'),
              );
              return;
            }
            orderedPayloads.add(fragment);
          }

          final jsonString = orderedPayloads.join();
          _logHistoryDebug(
            'History reassembled from ${fragments.length}/$totalFrames frames: ${jsonEncode(jsonString)}',
          );
          completer.complete(jsonString);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    try {
      if (historyCharacteristic.isNotifying) {
        await historyCharacteristic.setNotifyValue(false);
        _logHistoryDebug('History notifications reset before refresh');
        await Future.delayed(const Duration(milliseconds: 120));
      }

      await historyCharacteristic.setNotifyValue(true);
      _logHistoryDebug('History notifications enabled for one-shot refresh');
      await Future.delayed(const Duration(milliseconds: 180));

      _logHistoryDebug('Requesting history transfer from device');
      await startSendCharacteristic.write(const [0x01], withoutResponse: false);
      return await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      await subscription.cancel();
      if (historyCharacteristic.isNotifying) {
        try {
          await historyCharacteristic.setNotifyValue(false);
          _logHistoryDebug('History notifications disabled');
        } catch (_) {}
      }
    }
  }

  List<FocusRecord> _parseHistoryRecords(String jsonString) {
    final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
    final records = (jsonMap['records'] as List<dynamic>)
        .map((r) => FocusRecord.fromJson(r as Map<String, dynamic>))
        .toList();
    _logHistoryDebug('Parsed history records count: ${records.length}');
    return records;
  }

  Future<void> _ensurePreferredMtu(BluetoothDevice device) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final mtu = await device.requestMtu(BleConstants.preferredMtu);
      _logHistoryDebug(
          'Requested MTU ${BleConstants.preferredMtu}, negotiated MTU $mtu');
    } catch (e) {
      _logHistoryDebug('Request MTU ${BleConstants.preferredMtu} failed: $e');
    }
  }

  void _logHistoryDebug(String message) {
    if (!kDebugMode) return;
    debugPrint('[BLE][history] $message');
  }

  Future<void> writeDeviceTimePayload(Map<String, dynamic> payload) async {
    if (_charTimeSync == null) {
      throw Exception('未找到时间同步特征值(0003)');
    }
    final bytes = utf8.encode(jsonEncode(payload));
    await _charTimeSync!.write(bytes, withoutResponse: false);
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _charToday = null;
    _charHistory = null;
    _charTimeSync = null;
    _charStartSend = null;
    _connectionState = BleConnectionState.disconnected;
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
  }
}
