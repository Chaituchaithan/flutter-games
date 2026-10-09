import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_exception.dart';
import 'dev_proxy.dart';

/// API host/port. Resolution order:
/// 1. explicit `--dart-define=API_BASE_URL=…` (wins — staging/prod/relay);
/// 2. the local proxy (`tools/cors_proxy.dart`) when the proxy switch is ON
///    (see `dev_proxy.dart`) — needed on web, since the gateway sends no CORS
///    headers;
/// 3. the dev gateway default.
/// Point this at a staging/prod HTTPS host before release (and drop the Android
/// cleartext rule).
const _apiOverride = String.fromEnvironment('API_BASE_URL');
const _remoteBaseUrl = 'http://169.58.184.121:30080/api/v1';
final _baseUrl = _apiOverride.isNotEmpty
    ? _apiOverride
    : (kUseProxy ? '$kProxyHttpBase/api/v1' : _remoteBaseUrl);

/// Thin wrapper over Dio: attaches the auth bearer token and maps raw
/// `DioException`s into [AppException] so repositories stay transport-agnostic.
///
/// Not yet pointed at a live backend — remote sources are still off by default
/// (repositories use their static source). See docs/INTEGRATION_PLAN.md.
class ApiClient {
  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              // Trailing slash so a base path like `/api/v1` is preserved when a
              // relative path is appended (see [_rel]).
              baseUrl: _baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              contentType: 'application/json',
            )) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  String? _token;

  /// Invoked when a request is still 401 after a token refresh was attempted.
  /// The app wires this to sign out + show the "session expired" dialog.
  /// (A 403 is "signed in but not allowed" — reported as an error, never a
  /// sign-out.)
  void Function()? onUnauthorized;

  /// Refreshes the access token (POST /auth/refresh with the refresh token);
  /// resolves true when a new token was set. The access token lives 15 min,
  /// so any call after that first gets a 401 — this lets it transparently
  /// refresh and retry once instead of signing the player out.
  Future<bool> Function()? onRefreshToken;
  Future<bool>? _refreshing;

  /// Set/clear the bearer token attached to every request (see AuthService).
  set authToken(String? token) => _token = token;

  /// Strip a leading slash so the path stays relative to the base URL's path
  /// (Dio/Uri treat a leading-slash path as host-absolute, dropping `/api/v1`).
  String _rel(String path) => path.startsWith('/') ? path.substring(1) : path;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(path, () => _dio.get(_rel(path), queryParameters: query));

  Future<dynamic> post(String path, {Object? body}) =>
      _send(path, () => _dio.post(_rel(path), data: body));

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(path, () => _dio.patch(_rel(path), data: body));

  Future<dynamic> delete(String path, {Object? body}) =>
      _send(path, () => _dio.delete(_rel(path), data: body));

  /// Auth endpoints (login, refresh, guest, …) never trigger a refresh/retry:
  /// their 401 means bad credentials, not an expired session.
  static bool _isAuthPath(String path) => RegExp(r'^/?(auth|guest|oauth|otp)/').hasMatch(path);

  Future<dynamic> _send(String path, Future<Response<dynamic>> Function() run, {bool retried = false}) async {
    try {
      final res = await run();
      return res.data;
    } on DioException catch (e) {
      final expired = e.response?.statusCode == 401 && _token != null && !_isAuthPath(path);
      if (expired && !retried && onRefreshToken != null && await _refreshOnce()) {
        return _send(path, run, retried: true);
      }
      throw _map(e, notify: !_isAuthPath(path));
    }
  }

  /// One refresh at a time: concurrent 401s wait for the same refresh.
  Future<bool> _refreshOnce() {
    return _refreshing ??= () async {
      try {
        return await onRefreshToken!();
      } on Object catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  AppException _map(DioException e, {bool notify = true}) {
    final code = e.response?.statusCode;
    final kind = switch (e.type) {
      DioExceptionType.connectionError => AppErrorKind.offline,
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        AppErrorKind.timeout,
      _ => switch (code ?? 0) {
          401 || 403 => AppErrorKind.unauthorized,
          404 => AppErrorKind.notFound,
          >= 500 => AppErrorKind.server,
          _ => AppErrorKind.unknown,
        },
    };
    // Prefer the server's own message (envelope: {"error":"CODE","message":"…"}).
    final data = e.response?.data;
    final serverMsg = (data is Map && data['message'] is String) ? data['message'] as String : null;
    final message = serverMsg ??
        switch (kind) {
          AppErrorKind.offline => "You're offline. Check your connection.",
          AppErrorKind.timeout => 'The request timed out. Try again.',
          AppErrorKind.unauthorized => 'Please sign in again.',
          AppErrorKind.notFound => 'Not found.',
          AppErrorKind.server => 'Something went wrong on our end.',
          AppErrorKind.unknown => 'Something went wrong. Try again.',
        };
    // Only a 401 (that survived the refresh) is an expired session, and only
    // when we actually sent a token — a failed login also returns 401 but must
    // NOT sign the (guest) user out. A 403 is a permission error, not expiry.
    if (notify && code == 401 && _token != null && onUnauthorized != null) {
      // Defer so we don't re-enter Dio while an error is unwinding.
      Future.microtask(onUnauthorized!);
    }
    return AppException(message, kind: kind, statusCode: code);
  }
}

/// App-wide client. Overridden in tests; auth token set by the session layer.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
