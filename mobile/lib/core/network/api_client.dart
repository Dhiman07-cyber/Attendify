import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../storage/local_storage.dart';
import 'api_endpoints.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;
  final LocalStorage _storage = LocalStorage();

  ApiClient._internal() {
    dio = Dio(BaseOptions(
      baseUrl: ApiEndpoints.baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final customUrl = await _storage.getCustomApiBaseUrl();
        if (customUrl != null && customUrl.isNotEmpty) {
          options.baseUrl = ApiEndpoints.normalizeBaseUrl(customUrl);
        } else {
          options.baseUrl = ApiEndpoints.baseUrl;
        }
        final token = await _storage.getAccessToken();
        if (token != null && token.isNotEmpty && token != 'demo_token') {
          options.headers['Authorization'] = 'Bearer $token';
        } else if (token == 'demo_token') {
          await _storage.clearAuth();
        }

        final path = options.path;
        final isAuthEndpoint = path.contains('/auth/login') ||
            path.contains('/auth/register') ||
            path.contains('/auth/google') ||
            path.contains('/auth/refresh') ||
            path.contains('/auth/forgot-password') ||
            path.contains('/auth/reset-password');

        if (!isAuthEndpoint && (token == null || token.isEmpty || token == 'demo_token')) {
          if (kDebugMode) {
            debugPrint('[API BLOCKED] Prevented unauthenticated request while logged out: $path');
          }
          return handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: 'User is not authenticated.',
          ));
        }

        if (kDebugMode) {
          debugPrint('[API REQ] ${options.method} ${options.baseUrl}${options.path}');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          debugPrint('[API RES] ${response.statusCode} ${response.requestOptions.path}');
        }
        return handler.next(response);
      },
      onError: (DioException error, handler) async {
        if (kDebugMode) {
          debugPrint('[API ERR] ${error.response?.statusCode} ${error.requestOptions.path}: ${error.message}');
        }
        final path = error.requestOptions.path;
        final isAuthEndpoint = path.contains('/auth/login') ||
            path.contains('/auth/register') ||
            path.contains('/auth/refresh');

        if (error.response?.statusCode == 401 && !isAuthEndpoint) {
          // Attempt token refresh exactly once
          final refreshToken = await _storage.getRefreshToken();
          if (refreshToken != null && refreshToken.isNotEmpty && refreshToken != 'demo_refresh') {
            try {
              final customUrl = await _storage.getCustomApiBaseUrl();
              final activeBaseUrl = (customUrl != null && customUrl.isNotEmpty)
                  ? ApiEndpoints.normalizeBaseUrl(customUrl)
                  : ApiEndpoints.baseUrl;
              final refreshDio = Dio(BaseOptions(
                baseUrl: activeBaseUrl,
                connectTimeout: const Duration(seconds: 60),
                receiveTimeout: const Duration(seconds: 60),
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ));
              final response = await refreshDio.post(
                ApiEndpoints.refresh,
                data: {'refresh_token': refreshToken},
              );
              if (response.statusCode == 200) {
                final newAccess = response.data['access_token'];
                final newRefresh = response.data['refresh_token'];
                await _storage.saveTokens(accessToken: newAccess, refreshToken: newRefresh);

                // Retry failed request with new access token
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newAccess';
                final cloneReq = await dio.fetch(opts);
                return handler.resolve(cloneReq);
              }
            } on DioException catch (refreshErr) {
              // Only clear auth if refresh token was explicitly rejected as invalid/expired (401/400)
              if (refreshErr.response?.statusCode == 401 || refreshErr.response?.statusCode == 400) {
                await _storage.clearAuth();
              }
            } catch (_) {
              // Network/unforeseen error: do not eagerly clear saved credentials
            }
          }
        }
        return handler.next(error);
      },
    ));
  }
}
