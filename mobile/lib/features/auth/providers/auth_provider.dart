import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/storage/local_storage.dart';
import '../../../shared/models/user_model.dart';
import '../../profile/providers/profile_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../setup/providers/setup_provider.dart';
import '../../today/providers/today_provider.dart';
import '../../subjects/providers/subjects_provider.dart';
import '../../calendar/providers/calendar_provider.dart';
import '../../analytics/providers/analytics_provider.dart';
import '../../holidays/providers/holidays_provider.dart';
import '../../../shared/providers/semesters_provider.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isInitialChecking;
  final bool isSubmitting;
  final bool isGoogleLoading;
  final String? errorMessage;
  final UserModel? user;

  AuthState({
    required this.isAuthenticated,
    bool? isLoading,
    this.isInitialChecking = false,
    bool isSubmitting = false,
    this.isGoogleLoading = false,
    this.errorMessage,
    this.user,
  }) : isSubmitting = isSubmitting || (isLoading ?? false);

  /// Convenience getter for backward compatibility
  bool get isLoading => isInitialChecking || isSubmitting || isGoogleLoading;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    bool? isInitialChecking,
    bool? isSubmitting,
    bool? isGoogleLoading,
    String? errorMessage,
    UserModel? user,
  }) {
    final effectiveSubmitting = isSubmitting ?? (isLoading ?? this.isSubmitting);
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isInitialChecking: isInitialChecking ?? this.isInitialChecking,
      isSubmitting: effectiveSubmitting,
      isGoogleLoading: isGoogleLoading ?? this.isGoogleLoading,
      errorMessage: errorMessage,
      user: user ?? this.user,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref? _ref;
  final ApiClient _client = ApiClient();
  final LocalStorage _storage = LocalStorage();
  GoogleSignIn? _cachedGoogleSignIn;

  GoogleSignIn _getGoogleSignIn() {
    if (_cachedGoogleSignIn != null) return _cachedGoogleSignIn!;
    final String? clientId = AppConfig.googleServerClientId.isNotEmpty
        ? AppConfig.googleServerClientId
        : null;
    _cachedGoogleSignIn = GoogleSignIn(
      clientId: kIsWeb ? clientId : null,
      serverClientId: kIsWeb ? null : clientId,
      scopes: const ['email', 'profile'],
    );
    return _cachedGoogleSignIn!;
  }

  AuthNotifier([this._ref]) : super(AuthState(isAuthenticated: false, isInitialChecking: true)) {
    checkInitialAuth();
  }

  void invalidateUserData() {
    final ref = _ref;
    if (ref != null) {
      ref.invalidate(profileProvider);
      ref.invalidate(dashboardProvider);
      ref.invalidate(setupProvider);
      ref.invalidate(todayProvider);
      ref.invalidate(subjectsProvider);
      ref.invalidate(calendarProvider);
      ref.invalidate(analyticsProvider);
      ref.invalidate(holidaysProvider);
      ref.invalidate(semestersProvider);
    }
  }

  void setCustomError(String message) {
    state = state.copyWith(
      errorMessage: message,
      isInitialChecking: false,
      isSubmitting: false,
      isGoogleLoading: false,
    );
  }

  String _parseErrorDetail(dynamic detail, {String defaultMsg = 'An error occurred.'}) {
    if (detail == null) return defaultMsg;
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] != null) {
        final msg = first['msg'].toString();
        if (msg.contains('valid email')) {
          return 'Please enter a valid email address.';
        }
        return msg;
      }
      return first.toString();
    }
    if (detail is Map) {
      return detail['msg']?.toString() ?? detail['message']?.toString() ?? detail.toString();
    }
    return detail.toString();
  }

  Future<void> checkInitialAuth() async {
    final token = await _storage.getAccessToken();
    final cachedUser = await _storage.getCachedUser();

    if (token == null || token.isEmpty || token == 'demo_token') {
      await _storage.clearAuth();
      state = AuthState(isAuthenticated: false, isInitialChecking: false);
      return;
    }

    // Immediately restore cached session so there is zero flash of login/onboarding screen
    if (cachedUser != null) {
      state = state.copyWith(
        isAuthenticated: true,
        isInitialChecking: false,
        user: cachedUser,
      );
    } else {
      state = state.copyWith(isInitialChecking: true);
    }

    try {
      final resp = await _client.dio.get(ApiEndpoints.me);
      if (resp.statusCode == 200) {
        final user = UserModel.fromJson(resp.data);
        await _storage.saveUser(user);
        await _storage.setOnboarded(true);
        state = state.copyWith(
          isAuthenticated: true,
          isInitialChecking: false,
          user: user,
        );
      }
    } on DioException catch (dioErr) {
      if (dioErr.response?.statusCode == 401) {
        // Access token rejected and refresh interceptor could not refresh
        await _storage.clearAuth();
        state = AuthState(isAuthenticated: false, isInitialChecking: false);
      } else {
        // Network timeout / connection error / server starting up:
        // Preserve user state if cached user exists
        state = state.copyWith(isInitialChecking: false);
      }
    } catch (_) {
      state = state.copyWith(isInitialChecking: false);
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      final resp = await _client.dio.post(
        ApiEndpoints.login,
        data: {'email': email.trim(), 'password': password},
      );
      final data = resp.data;
      await _storage.saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      final user = UserModel(
        id: data['user_id'],
        email: data['email'],
        fullName: data['full_name'],
        avatarInitial: data['full_name'].isNotEmpty ? data['full_name'][0].toUpperCase() : 'A',
        isActive: true,
      );
      await _storage.saveUser(user);
      await _storage.setOnboarded(true);
      state = state.copyWith(
        isAuthenticated: true,
        isSubmitting: false,
        user: user,
      );
      invalidateUserData();
      final ref = _ref;
      if (ref != null) {
        ref.read(semestersProvider.notifier).loadSemesters();
      }
      return true;
    } catch (e) {
      String msg = 'Invalid email or password.';
      if (e is DioException) {
        if (e.response?.data is Map && e.response?.data['detail'] != null) {
          msg = _parseErrorDetail(e.response!.data['detail'], defaultMsg: msg);
        } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError) {
          msg = "Couldn't connect to server. Check your connection.";
        }
      }
      state = state.copyWith(
        isAuthenticated: false,
        isSubmitting: false,
        errorMessage: msg,
      );
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    String? universityName,
    String? courseName,
    int? semesterNumber,
    bool seedDemoData = false,
  }) async {
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      final resp = await _client.dio.post(
        ApiEndpoints.register,
        data: {
          'email': email.trim(),
          'password': password,
          'full_name': fullName.trim(),
          'university_name': universityName,
          'course_name': courseName,
          'current_semester_number': semesterNumber ?? 1,
          'seed_demo_data': seedDemoData,
        },
      );
      final data = resp.data;
      await _storage.saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      final user = UserModel(
        id: data['user_id'],
        email: data['email'],
        fullName: data['full_name'],
        avatarInitial: data['full_name'].isNotEmpty ? data['full_name'][0].toUpperCase() : 'A',
        isActive: true,
      );
      await _storage.saveUser(user);
      await _storage.setOnboarded(true);
      state = state.copyWith(
        isAuthenticated: true,
        isSubmitting: false,
        user: user,
      );
      invalidateUserData();
      final ref = _ref;
      if (ref != null) {
        ref.read(semestersProvider.notifier).loadSemesters();
      }
      return true;
    } catch (e) {
      String msg = 'Registration failed. Please check your information.';
      if (e is DioException) {
        if (e.response?.data is Map && e.response?.data['detail'] != null) {
          msg = _parseErrorDetail(e.response!.data['detail'], defaultMsg: msg);
        } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError) {
          msg = "Couldn't connect to server. Check your connection.";
        }
      }
      state = state.copyWith(
        isAuthenticated: false,
        isSubmitting: false,
        errorMessage: msg,
      );
      return false;
    }
  }

  Future<bool> signInWithGoogle({
    String? mockIdToken,
    String? mockAccessToken,
    String? mockEmail,
    String? mockName,
  }) async {
    state = state.copyWith(isGoogleLoading: true, errorMessage: null);
    try {
      String? idToken = mockIdToken;
      String? accessToken = mockAccessToken;
      String? email = mockEmail;
      String? name = mockName;

      if (idToken == null && accessToken == null) {
        final GoogleSignIn googleSignIn = _getGoogleSignIn();
        // Trigger explicit Google account selection directly.
        // Bypasses passive FedCM signInSilently() which hangs indefinitely in desktop browsers.
        final GoogleSignInAccount? account = await googleSignIn.signIn();
        if (account == null) {
          state = state.copyWith(isGoogleLoading: false);
          return false;
        }
        final GoogleSignInAuthentication auth = await account.authentication;
        idToken = auth.idToken;
        accessToken = auth.accessToken;
        email = account.email;
        name = account.displayName;
      }

      final payload = <String, dynamic>{
        if (idToken != null && idToken.isNotEmpty) 'id_token': idToken,
        if (accessToken != null && accessToken.isNotEmpty) 'access_token': accessToken,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        if (name != null && name.trim().isNotEmpty) 'full_name': name.trim(),
      };

      if (!payload.containsKey('id_token') && !payload.containsKey('access_token')) {
        state = state.copyWith(
          isAuthenticated: false,
          isGoogleLoading: false,
          errorMessage: 'Google authentication did not return credentials. Check your Google Cloud origins.',
        );
        return false;
      }

      final resp = await _client.dio.post(
        ApiEndpoints.googleAuth,
        data: payload,
      );

      final data = resp.data;
      await _storage.saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      final user = UserModel(
        id: data['user_id'],
        email: data['email'],
        fullName: data['full_name'],
        avatarInitial: data['full_name'].isNotEmpty ? data['full_name'][0].toUpperCase() : 'A',
        isActive: true,
      );
      await _storage.saveUser(user);
      await _storage.setOnboarded(true);
      state = state.copyWith(
        isAuthenticated: true,
        isGoogleLoading: false,
        user: user,
      );
      invalidateUserData();
      final ref = _ref;
      if (ref != null) {
        ref.read(semestersProvider.notifier).loadSemesters();
      }
      return true;
    } on PlatformException catch (pEx, st) {
      if (kDebugMode) {
        debugPrint('[Google Auth PlatformException] ${pEx.code}: ${pEx.message}\n$st');
      }
      String msg = 'Google Sign-In is unavailable on this device platform (${pEx.code}).';
      final pExMsg = pEx.message ?? '';

      if (pEx.code == 'popup_closed_by_user' ||
          pEx.code == 'sign_in_canceled' ||
          pExMsg.toLowerCase().contains('canceled') ||
          pExMsg.toLowerCase().contains('cancelled')) {
        msg = 'Google Sign-In was cancelled.';
      } else if (pEx.code.contains('unregistered_origin') || pExMsg.contains('unregistered_origin')) {
        msg = 'Google Sign-In: Current origin/port is not authorized in Google Cloud Console. Add this localhost port to Authorized JavaScript Origins.';
      } else if (pEx.code == 'sign_in_failed' ||
          pExMsg.contains('10') ||
          pExMsg.contains('s0.d') ||
          pExMsg.contains('DEVELOPER_ERROR') ||
          pExMsg.contains('ApiException: 10')) {
        msg = 'Google Sign-In setup error (Developer Error 10): This APK\'s signing certificate (SHA-1) is not registered in Google Cloud Console for com.attendhub.attendhub.';
      } else if (pExMsg.contains('7') || pExMsg.toLowerCase().contains('network_error')) {
        msg = 'Network error during Google Sign-In. Please check your internet connection.';
      } else if (pExMsg.startsWith('s0.') || pExMsg.contains('ApiException')) {
        msg = 'Google Sign-In failed (${pEx.code}). Please verify Google Play Services.';
      } else if (pExMsg.isNotEmpty) {
        msg = pExMsg;
      }

      state = state.copyWith(
        isAuthenticated: false,
        isGoogleLoading: false,
        errorMessage: msg,
      );
      return false;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Google Auth Error] $e\n$st');
      }
      String msg = 'Google authentication failed.';
      if (e is DioException) {
        if (e.response?.data is Map && e.response?.data['detail'] != null) {
          msg = _parseErrorDetail(e.response!.data['detail'], defaultMsg: msg);
        } else if (e.response?.data is String && (e.response!.data as String).isNotEmpty) {
          msg = e.response!.data as String;
        } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError) {
          msg = "Couldn't connect to server. Check your connection.";
        } else if (e.message != null && e.message!.isNotEmpty) {
          msg = e.message!;
        }
      } else {
        final errStr = e.toString().replaceAll('Exception:', '').trim();
        if (errStr.contains('DOMException') ||
            errStr.contains('AbortError') ||
            errStr.contains('popup_closed') ||
            errStr.contains('user cancelled')) {
          msg = 'Google Sign-In was cancelled or closed.';
        } else if (errStr.contains('unregistered_origin')) {
          msg = 'Google Sign-In: Current origin/port is not authorized in Google Cloud Console. Add this localhost port to Authorized JavaScript Origins.';
        } else if (errStr.contains('10') || errStr.contains('s0.d')) {
          msg = 'Google Sign-In setup error (Developer Error 10): This APK\'s signing certificate (SHA-1) is not registered in Google Cloud Console for com.attendhub.attendhub.';
        } else {
          msg = errStr.isNotEmpty ? 'Google Sign-In: $errStr' : 'Google authentication failed.';
        }
      }
      state = state.copyWith(
        isAuthenticated: false,
        isGoogleLoading: false,
        errorMessage: msg,
      );
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _client.dio.post(ApiEndpoints.logout).timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await _cachedGoogleSignIn?.signOut().timeout(const Duration(seconds: 1));
    } catch (_) {}
    _cachedGoogleSignIn = null;
    await _storage.clearAuth();
    await _storage.clearSemesterCache();
    state = AuthState(isAuthenticated: false, isInitialChecking: false);
    final ref = _ref;
    if (ref != null) {
      ref.read(semestersProvider.notifier).clear();
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});
