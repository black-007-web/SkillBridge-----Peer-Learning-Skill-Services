import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureSupabaseSessionStorage extends LocalStorage {
  SecureSupabaseSessionStorage(String projectUrl)
    : _sessionKey =
          'sb-${Uri.parse(projectUrl).host.split('.').first}-auth-token';

  static const _secureStorage = FlutterSecureStorage();
  final String _sessionKey;
  late final SharedPreferencesLocalStorage _legacy =
      SharedPreferencesLocalStorage(persistSessionKey: _sessionKey);

  @override
  Future<void> initialize() async {
    await _legacy.initialize();
    final alreadySecure = await _secureStorage.containsKey(key: _sessionKey);
    final existing = await _legacy.accessToken();
    if (!alreadySecure && existing != null) {
      await _secureStorage.write(key: _sessionKey, value: existing);
    }
    if (existing != null) {
      await _legacy.removePersistedSession();
    }
  }

  @override
  Future<String?> accessToken() => _secureStorage.read(key: _sessionKey);

  @override
  Future<bool> hasAccessToken() async =>
      await _secureStorage.containsKey(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _secureStorage.write(key: _sessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() =>
      _secureStorage.delete(key: _sessionKey);
}

class SecurePkceStorage extends GotrueAsyncStorage {
  const SecurePkceStorage();
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> getItem({required String key}) =>
      _storage.read(key: 'pkce:$key');

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: 'pkce:$key', value: value);

  @override
  Future<void> removeItem({required String key}) =>
      _storage.delete(key: 'pkce:$key');
}
