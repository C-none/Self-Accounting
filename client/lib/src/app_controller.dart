import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ledger_client/src/api_client.dart';
import 'package:ledger_client/src/models.dart';

class AppController extends ChangeNotifier {
  AppController(this.api);

  final ApiClient api;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _serviceBaseUrlKey = 'service_base_url';

  bool initialized = false;
  bool busy = false;
  String? token;
  String? deviceId;
  String? lastError;
  BootstrapData? bootstrapData;

  bool get isPaired => token != null && bootstrapData != null;

  Future<void> initialize() async {
    final storedBaseUrl = await _storage.read(key: _serviceBaseUrlKey);
    if (storedBaseUrl != null && storedBaseUrl.trim().isNotEmpty) {
      api.setBaseUrl(storedBaseUrl);
    }
    token = await _storage.read(key: 'device_token');
    deviceId = await _storage.read(key: 'device_id');
    if (token != null && token!.isNotEmpty) {
      try {
        bootstrapData = await api.bootstrap(token!);
      } catch (e) {
        if (e is ApiException && e.code == 'unauthorized') {
          token = null;
          deviceId = null;
          await _storage.delete(key: 'device_token');
          await _storage.delete(key: 'device_id');
        } else {
          lastError = e.toString();
        }
      }
    }
    initialized = true;
    notifyListeners();
  }

  Future<void> updateServiceEndpoint({
    required String host,
    required String port,
  }) async {
    final baseUrl = ApiClient.buildServiceBaseUrl(host: host, port: port);
    api.setBaseUrl(baseUrl);
    await _storage.write(key: _serviceBaseUrlKey, value: baseUrl);
    lastError = null;
  }

  Future<PairingStartResult> startPairing() async {
    return _run(() async {
      final json = await api.pairStart(token: token);
      return PairingStartResult.fromJson(json);
    });
  }

  Future<void> confirmPairing({
    required String code,
    required String deviceName,
    required String platform,
  }) async {
    await _run(() async {
      final json = await api.pairConfirm(
        pairingCode: code,
        deviceName: deviceName,
        platform: platform,
      );
      token = json['device_token'] as String;
      deviceId = json['device_id'] as String;
      await _storage.write(key: 'device_token', value: token);
      await _storage.write(key: 'device_id', value: deviceId);
      bootstrapData = await api.bootstrap(token!);
    });
  }

  Future<void> refreshBootstrap() async {
    if (token == null) {
      return;
    }
    await _run(() async {
      bootstrapData = await api.bootstrap(token!);
    });
  }

  Future<void> updateCurrentDeviceName(String name) async {
    if (token == null) {
      return;
    }
    await _run(() async {
      await api.updateCurrentDevice(token!, name);
      bootstrapData = await api.bootstrap(token!);
    });
  }

  Future<void> logout() async {
    token = null;
    deviceId = null;
    bootstrapData = null;
    await _storage.delete(key: 'device_token');
    await _storage.delete(key: 'device_id');
    notifyListeners();
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      return await action();
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

class PairingStartResult {
  PairingStartResult({
    required this.pairingCode,
    required this.expiresAt,
    required this.delivery,
  });

  final String? pairingCode;
  final int? expiresAt;
  final String delivery;

  bool get isConsoleOnly => pairingCode == null || pairingCode!.isEmpty;

  factory PairingStartResult.fromJson(Map<String, dynamic> json) {
    return PairingStartResult(
      pairingCode: json['pairing_code'] as String?,
      expiresAt: json['expires_at'] as int?,
      delivery: json['delivery'] as String? ?? 'response',
    );
  }
}
