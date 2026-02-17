import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'web_token_storage_stub.dart'
    if (dart.library.html) 'web_token_storage_web.dart' as web_storage;

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  late final Dio _dio;
  // flutter_secure_storage for native, localStorage for web
  final _storage = const FlutterSecureStorage();
  
  String? _token;
  Map<String, dynamic>? _user;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isAuthenticated => _token != null;

  String get _baseUrl {
    if (kIsWeb) return '/api';
    if (kDebugMode) return 'http://10.0.2.2:4040/api';
    return 'https://dipreport.com/api';
  }

  Future<void> init() async {
    try {
      if (kIsWeb) {
        _token = web_storage.readToken();
      } else {
        _token = await _storage.read(key: 'auth_token');
      }
      if (_token != null) {
        await fetchProfile();
      }
    } catch (e) {
      debugPrint('AuthService init error: $e');
    }
  }

  Future<bool> requestMagicLink(String email, {String? returnTo}) async {
    try {
      final platform = kIsWeb ? 'web' : 'mobile';
      final payload = <String, dynamic>{
        'email': email,
        'platform': platform,
      };
      if (returnTo != null && returnTo.isNotEmpty) {
        payload['return_to'] = returnTo;
      }

      final response = await _dio.post('/auth/magic-link', data: payload);
      return response.statusCode == 200;
    } catch (e) {
      print('AuthService: Request magic link error: $e');
      return false;
    }
  }

  Future<bool> fetchProfile() async {
    if (_token == null) return false;
    try {
      final response = await _dio.get(
        '/auth/user',
        options: Options(headers: {'Authorization': 'Bearer $_token'}),
      );
      if (response.statusCode == 200) {
        _user = response.data;
        return true;
      }
    } on DioException catch (e) {
      // Only clear token on explicit auth rejection (401/403)
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        debugPrint('AuthService: Token rejected (${e.response?.statusCode}), clearing.');
        _token = null;
        _user = null;
        if (kIsWeb) {
          web_storage.deleteToken();
        } else {
          await _storage.delete(key: 'auth_token');
        }
        notifyListeners();
        return false;
      }
      debugPrint('AuthService: Fetch profile network error: $e');
    } catch (e) {
      debugPrint('AuthService: Fetch profile error: $e');
    }
    return false;
  }

  Future<void> setToken(String token) async {
    _token = token;
    if (kIsWeb) {
      web_storage.writeToken(token);
    } else {
      await _storage.write(key: 'auth_token', value: token);
    }
    await fetchProfile();
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    if (kIsWeb) {
      web_storage.deleteToken();
    } else {
      await _storage.delete(key: 'auth_token');
    }
    notifyListeners();
  }
}
