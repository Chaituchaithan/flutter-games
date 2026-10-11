/// REST paths shared by every game (relative to the API base, `/api/v1`).
/// Source: the Portal Gateway API catalog (api-lab `endpoints.json`).
library;

abstract final class ApiEndpoints {
  // Auth
  static const authLogin = '/auth/login';
  static const authRegister = '/auth/register';
  static const authRefresh = '/auth/refresh';
  static const authLogout = '/auth/logout';
  static const authChangePassword = '/auth/change-password';
  static const guestCreate = '/guest/create';
  static const guestConvert = '/guest/convert';
  static const otpVerify = '/otp/verify';

  // Users / profile
  static const usersMe = '/users/me';
  static const usersMeProfile = '/users/me/profile';
  static String userProfile(String id) => '/users/$id/profile';

  // Social
  static const friends = '/friends';
  static const friendRequests = '/friends/requests';
  static const friendSuggestions = '/friends/suggested';
  static const leaderboard = '/leaderboard';
  static const tournaments = '/tournaments';
  static const inbox = '/inbox';

  // Economy
  static const wallet = '/wallet';
  static const dailyBonusStatus = '/sensitive/daily-bonus/status';
  static const dailyBonusClaim = '/sensitive/daily-bonus/claim';
  static const subscriptionPlans = '/sensitive/subscriptions/plans';
  static const subscriptionMy = '/sensitive/subscriptions/my';
  static const subscriptionSubscribe = '/sensitive/subscriptions/subscribe';
  static const subscriptionCancel = '/sensitive/subscriptions/cancel';
  static const storePacks = '/store/packs';

  // Matches
  static const myMatchHistory = '/matches/my-history';
}
