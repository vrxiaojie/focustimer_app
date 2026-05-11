import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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

  List<BluetoothDevice> _scanResults = [];
  List<BluetoothDevice> get scanResults => _scanResults;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  FocusTimerProvider() {
    _loadCachedData();
  }

  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedHistory = prefs.getString('cached_history');
      if (cachedHistory != null) {
        final jsonMap = jsonDecode(cachedHistory) as Map<String, dynamic>;
        _historyRecords = (jsonMap['records'] as List<dynamic>)
            .map((r) => FocusRecord.fromJson(r as Map<String, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (_) {}
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
    _isScanning = true;
    _scanResults = [];
    _errorMessage = null;
    notifyListeners();

    try {
      final devices = await _bleService.scanDevices();
      _scanResults = devices;
    } catch (e) {
      _errorMessage = '扫描失败: $e';
    }

    _isScanning = false;
    notifyListeners();
  }

  void stopScan() {
    _bleService.stopScan();
    _isScanning = false;
    notifyListeners();
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    _errorMessage = null;
    notifyListeners();

    final success = await _bleService.connectToDevice(device);
    if (success) {
      notifyListeners();
      // Auto sync data after connection
      await syncData();
    } else {
      _errorMessage = '连接失败';
    }
    notifyListeners();
    return success;
  }

  Future<void> disconnect() async {
    await _bleService.disconnect();
    _todayData = null;
    notifyListeners();
  }

  Future<void> syncData() async {
    final todayData = await _bleService.readTodayData();
    if (todayData != null) {
      _todayData = todayData;
    }

    final historyData = await _bleService.readHistoryData();
    if (historyData.isNotEmpty) {
      _historyRecords = historyData;
      await _cacheHistoryData();
    }

    notifyListeners();
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
}
