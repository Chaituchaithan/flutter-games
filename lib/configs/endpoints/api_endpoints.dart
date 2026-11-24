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
  static const authForgotPassword = '/auth/forgot-password';
  static const authForgotPasswordVerify = '/auth/forgot-password/verify';
  static const authResetPassword = '/auth/reset-password';
  static const guestCreate = '/guest/create';
  static const guestConvert = '/guest/convert';
  static const otpSend = '/otp/send';
  static const otpVerify = '/otp/verify';
  static const otpLoginSend = '/otp/login/send';
  static const otpLoginVerify = '/otp/login/verify';

  // Users / profile
  static const usersMe = '/users/me';
  static const usersMeProfile = '/users/me/profile';
  static String userProfile(String id) => '/users/$id/profile';
  static const usersMeInventory = '/users/me/inventory';
  static const usersMePrivacy = '/users/me/privacy';
  static const usersMePreferences = '/users/me/preferences';
  static String usersMeAddress(String kind) => '/users/me/addresses/$kind';
  static const cosmeticsAvatars = '/cosmetics/avatars';
  static String cosmeticsAvatarEquip(int id) => '/cosmetics/avatars/$id/equip';

  // Devices and sessions (02-profile-and-sessions.md §10, §11)
  static const devices = '/devices';
  static const devicesRegister = '/devices/register';
  static String device(int id) => '/devices/$id';
  static String devicePushToken(int id) => '/devices/$id/push-token';
  static const sessions = '/sessions';
  static String session(String id) => '/sessions/$id';

  // Social
  static const friends = '/friends';
  static const friendRequests = '/friends/requests';
  static const friendSuggestions = '/friends/suggested';
  // 09-social.md: friends, presence, chat, gifts, referrals, blocks.
  static const friendRequest = '/friends/request';
  static const friendRequestsPending = '/friends/requests/pending';
  static String friendRequestAccept(int id) => '/friends/request/$id/accept';
  static String friendRequestReject(int id) => '/friends/request/$id/reject';
  static String friend(String userId) => '/friends/$userId';
  static const presenceHeartbeat = '/presence/heartbeat';
  static const presenceFriendsOnline = '/presence/friends-online';
  static const presenceOnlineCount = '/presence/online-count';
  static String chatSend(String roomType, String roomId) =>
      '/chat/$roomType/${Uri.encodeComponent(roomId)}/send';
  static String chatHistory(String roomType, String roomId) =>
      '/chat/$roomType/${Uri.encodeComponent(roomId)}/history';
  static const giftsSend = '/gifts/send';
  static const giftsReceived = '/gifts/received';
  static const giftsSent = '/gifts/sent';
  static const referralApply = '/referrals/apply';
  static const blocks = '/blocks';
  static String block(String userId) => '/blocks/$userId';
  static const leaderboard = '/leaderboard';
  static const tournaments = '/tournaments';
  // Tournaments (06-tournaments.md). `{id}` is the tournament's UUID.
  static String tournament(String id) => '/tournaments/$id';
  static String tournamentRegister(String id) => '/tournaments/$id/register';
  static String tournamentUnregister(String id) => '/tournaments/$id/unregister';
  static String tournamentMyTable(String id) => '/tournaments/$id/my-table';
  static String tournamentStandings(String id) => '/tournaments/$id/standings';
  static String tournamentRounds(String id) => '/tournaments/$id/rounds';
  static String tournamentBracket(String id) => '/tournaments/$id/bracket';
  static const inbox = '/inbox';

  // Inbox and notifications (10-inbox-and-notifications.md). Inbox ids are numbers.
  static String inboxMessage(int id) => '/inbox/$id';
  static String inboxRead(int id) => '/inbox/$id/read';
  static String inboxClaim(int id) => '/inbox/$id/claim-reward';
  static const notifications = '/notifications';
  static const notificationPreferences = '/notifications/preferences';

  // Economy
  static const walletBalance = '/wallet/balance';
  static const walletLedger = '/wallet/ledger';
  static const walletTransfer = '/wallet/transfer';
  static const referralMyCode = '/referrals/my-code';
  static const referralStats = '/referrals/stats';
  static const dailyBonusStatus = '/sensitive/daily-bonus/status';
  static const dailyBonusClaim = '/sensitive/daily-bonus/claim';
  static const subscriptionPlans = '/sensitive/subscriptions/plans';
  static const subscriptionMy = '/sensitive/subscriptions/my';
  static const subscriptionSubscribe = '/sensitive/subscriptions/subscribe';
  static const subscriptionCancel = '/sensitive/subscriptions/cancel';
  static const storePacks = '/store/packs';

  // Store (11-store.md). Shop/IAP/ad-free are `/sensitive/` (device check).
  static const shopItems = '/sensitive/shop/items';
  static String shopItem(int id) => '/sensitive/shop/items/$id';
  static const shopPurchase = '/sensitive/shop/purchase';
  static const shopPurchaseSandbox = '/sensitive/shop/purchase/sandbox';
  static const iapVerify = '/sensitive/iap/verify';
  static const iapHistory = '/sensitive/iap/history';
  static const adFreeStatus = '/sensitive/ad-free/status';
  static const adsFlow = '/me/ads/flow';
  static String cosmeticsAvatarPurchase(int id) => '/cosmetics/avatars/$id/purchase';
  static const cosmeticsPowerUps = '/cosmetics/power-ups';
  static String cosmeticsPowerUpPurchase(int id) => '/cosmetics/power-ups/$id/purchase';

  // Rewards (07-rewards.md). Path ids are numbers; bonus games also take a code.
  static const welcomeBonusMe = '/welcome-bonus/me';
  static const welcomeBonusClaim = '/welcome-bonus/claim';
  static const questsActive = '/sensitive/quests/active';
  static const questsMyProgress = '/sensitive/quests/my-progress';
  static String questClaim(int id) => '/sensitive/quests/$id/claim';
  static const achievements = '/achievements';
  static const achievementsMy = '/achievements/my';
  static String achievementClaim(int id) => '/achievements/$id/claim';
  static const bonusGames = '/bonus-games';
  static String bonusGame(String idOrCode) => '/bonus-games/${Uri.encodeComponent(idOrCode)}';
  static String bonusGamePlay(String idOrCode) => '/bonus-games/${Uri.encodeComponent(idOrCode)}/play';
  static const bonusGamePlaysMe = '/bonus-games/plays/me';

  // Game catalogue (numeric ids: find a game's id by `code` in GET /games)
  static const games = '/games';
  static String gameModes(int id) => '/games/$id/modes';
  static String gameVariants(int id) => '/games/$id/variants';
  static String gameStakes(int id) => '/games/$id/stakes';
  static String game(int id) => '/games/$id';
  static String gamePowerUps(int id) => '/games/$id/power-ups';
  static String gameConfig(int id) => '/games/$id/config';
  static String gameAchievements(int id) => '/games/$id/achievements';

  // Bingo live rooms (05-matchmaking-and-rooms.md §3). Matchmaking itself is
  // on each game's socket: the gateway's /matchmaking/... routes are retired.
  static const liveRooms = '/live-rooms';
  static String liveRoom(String id) => '/live-rooms/$id';

  // Matches
  static const myMatchHistory = '/matches/my-history';
  static String match(String matchId) => '/matches/${Uri.encodeComponent(matchId)}';

  // Progress (08-progress-and-history.md). Game ids are numeric.
  static const progressionLevels = '/progression/levels';
  static const progressionRatings = '/progression/ratings';
  static String progressionStats(int gameId) => '/progression/$gameId/stats';
  static String leaderboardBoard(int gameId, String metric) => '/leaderboards/$gameId/$metric';
  static String leaderboardMyRank(int gameId, String metric) => '/leaderboards/$gameId/$metric/my-rank';

  // Safety (12-safety.md): reports, ban check, match flags.
  static const moderationReport = '/moderation/report';
  static const moderationMyReports = '/moderation/my-reports';
  static const moderationBanCheck = '/moderation/bans/check';
  static String matchFlag(String matchId) => '/matches/$matchId/flag';
}
