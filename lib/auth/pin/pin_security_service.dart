import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class PinSecurityService {
  PinSecurityService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _localAuth = localAuth ?? LocalAuthentication();

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  static const _kPinHash = 'pin_hash_v1';
  static const _kBiometricsEnabled = 'biometrics_enabled_v1';

  Future<bool> hasPin() async {
    final v = await _storage.read(key: _kPinHash);
    return v != null && v.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    final hash = _hashPin(pin);
    await _storage.write(key: _kPinHash, value: hash);
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _kPinHash);
    if (stored == null || stored.isEmpty) return false;
    return stored == _hashPin(pin);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kPinHash);
    await _storage.delete(key: _kBiometricsEnabled);
  }

  Future<bool> isBiometricsEnabled() async {
    final v = await _storage.read(key: _kBiometricsEnabled);
    return v == '1';
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    await _storage.write(key: _kBiometricsEnabled, value: enabled ? '1' : '0');
  }

  Future<bool> canUseBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      final can = await _localAuth.canCheckBiometrics;
      if (!can) return false;

      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    if (kIsWeb) return false;
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to continue',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  String _hashPin(String pin) {
    // Simple sha256 hash; secure_storage keeps it device protected.
    final bytes = utf8.encode('eclassiut:$pin');
    return sha256.convert(bytes).toString();
  }
}
