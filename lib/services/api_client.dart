import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_exception.dart';

/// Base URL is injected at build time: `--dart-define=API_BASE_URL=…`.
/// Never hardcode a real host or secrets here (see docs/INTEGRATION_PLAN.md §5).
const _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.aura.example',
);

/// Thin wrapper over Dio: attaches the auth bearer token and maps raw
/// `DioException`s into [AppException] so repositories stay transport-agnostic.
///
/// Not yet pointed at a live backend — remote sources are still off by default
/// (repositories use their static source). See docs/INTEGRATION_PLAN.md.
class ApiClient {
  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _baseUrl,
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

  /// Invoked once when a request comes back unauthorized (401/403). The app wires
  /// this to sign out + show the "session expired" dialog.
  void Function()? onUnauthorized;

  /// Set/clear the bearer token attached to every request (see AuthService).
  set authToken(String? token) => _token = token;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? body}) =>
      _send(() => _dio.post(path, data: body));

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(() => _dio.patch(path, data: body));

  Future<dynamic> delete(String path, {Object? body}) =>
      _send(() => _dio.delete(path, data: body));

  Future<dynamic> _send(Future<Response<dynamic>> Function() run) async {
    try {
      final res = await run();
      return res.data;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  AppException _map(DioException e) {
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
    final message = switch (kind) {
      AppErrorKind.offline => "You're offline. Check your connection.",
      AppErrorKind.timeout => 'The request timed out. Try again.',
      AppErrorKind.unauthorized => 'Please sign in again.',
      AppErrorKind.notFound => 'Not found.',
      AppErrorKind.server => 'Something went wrong on our end.',
      AppErrorKind.unknown => 'Something went wrong. Try again.',
    };
    if (kind == AppErrorKind.unauthorized && onUnauthorized != null) {
      // Defer so we don't re-enter Dio while an error is unwinding.
      Future.microtask(onUnauthorized!);
    }
    return AppException(message, kind: kind, statusCode: code);
  }
}

/// App-wide client. Overridden in tests; auth token set by the session layer.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
