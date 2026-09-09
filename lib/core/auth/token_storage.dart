import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../shared/models/auth_tokens.dart';

/// Persistência dos tokens de sessão em armazenamento seguro
/// (flutter_secure_storage — Keychain/Keystore/libsecret).
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Android v11+: Keystore AES-GCM por padrão (API 23+) com
            // resetOnError — dados são limpos (não lançam) se o Keystore
            // for invalidado (restore de backup, troca de biometria).
            aOptions: AndroidOptions(),
            // iOS: itens acessíveis apenas após o primeiro desbloqueio.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  static const _accessTokenKey = 'auth.access_token';
  static const _refreshTokenKey = 'auth.refresh_token';

  final FlutterSecureStorage _storage;

  Future<void> saveTokens(SessionTokens tokens) async {
    await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
  }

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}

/// Provider do armazenamento seguro de tokens.
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
