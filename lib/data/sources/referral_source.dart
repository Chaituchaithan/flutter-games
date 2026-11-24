import '../../configs/endpoints/api_endpoints.dart';
import '../../services/api_client.dart';
import '../../services/app_exception.dart';
import '../models/referral.dart';

/// Your invite code and its results (docs/services/09-social.md §5).
abstract class ReferralSource {
  Future<ReferralCode> myCode();
  Future<ReferralStats> stats();

  /// `POST /referrals/apply` once per account (`204`). [code] is sent
  /// trimmed and upper-cased: codes are case-sensitive (Known issues 9).
  Future<void> apply(String code);
}

/// Codes are 8 upper-case letters and digits; the server is case-sensitive.
String normalizeReferralCode(String code) => code.trim().toUpperCase();

/// The web host for invite links (`--dart-define=INVITE_LINK_HOST=...`).
/// Empty (no app domain yet) = the app's own scheme, like room join links.
const inviteLinkHost = String.fromEnvironment('INVITE_LINK_HOST');

/// The share link built on the device (there is no server link, §5a):
/// `https://<host>/invite?code=X`, or `royalearcade://invite?code=X`.
Uri inviteLink(String code, {String host = inviteLinkHost}) {
  final q = {'code': normalizeReferralCode(code)};
  return host.isEmpty
      ? Uri(scheme: 'royalearcade', host: 'invite', queryParameters: q)
      : Uri(scheme: 'https', host: host, path: '/invite', queryParameters: q);
}

/// The referral code in an invite link (`https://<host>/invite?code=X` or
/// `royalearcade://invite?code=X`), upper-cased; null when it isn't one.
String? parseInviteLink(Uri uri) {
  final isInvite = (uri.scheme == 'royalearcade' && uri.host == 'invite') ||
      ((uri.scheme == 'https' || uri.scheme == 'http') && uri.path == '/invite');
  if (!isInvite) return null;
  final code = normalizeReferralCode(uri.queryParameters['code'] ?? '');
  return code.isEmpty || code.length > 16 ? null : code;
}

/// Signed-out demo.
class StaticReferralSource implements ReferralSource {
  StaticReferralSource();

  bool _applied = false;

  @override
  Future<ReferralCode> myCode() async => const ReferralCode(code: 'DEMO2026');

  @override
  Future<ReferralStats> stats() async => const ReferralStats();

  @override
  Future<void> apply(String code) async {
    final c = normalizeReferralCode(code);
    if (c.isEmpty || c.length > 16) throw const AppException('', statusCode: 400, code: ApiErrorCode.validation, field: 'code');
    if (c == 'DEMO2026') throw const AppException('', statusCode: 400, code: ApiErrorCode.badRequest);
    if (_applied) throw const AppException('', statusCode: 409, code: ApiErrorCode.conflict);
    _applied = true;
  }
}

class RemoteReferralSource implements ReferralSource {
  const RemoteReferralSource(this._api);
  final ApiClient _api;

  static Map<String, dynamic> _body(Object? res) =>
      ((res is Map && res['data'] is Map ? res['data'] : res) as Map).cast<String, dynamic>();

  @override
  Future<ReferralCode> myCode() async => ReferralCode.fromJson(_body(await _api.get(ApiEndpoints.referralMyCode)));

  @override
  Future<ReferralStats> stats() async => ReferralStats.fromJson(_body(await _api.get(ApiEndpoints.referralStats)));

  @override
  Future<void> apply(String code) async {
    await _api.post(ApiEndpoints.referralApply, body: {'code': normalizeReferralCode(code)});
  }
}
