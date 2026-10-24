/// ONE place for deployment settings. The developer fills this in ONCE after deploying `ai-proxy/`.
/// Users never see or type any key or address: AI works silently, and if it is unreachable the app
/// keeps working with built-in rules.
///
/// Either edit the two defaults below, or pass them at build time:
///   flutter build apk --release --dart-define=AI_PROXY_URL=https://xyz.vercel.app --dart-define=AI_PROXY_TOKEN=...
const String kAiProxyUrl =
    String.fromEnvironment('AI_PROXY_URL', defaultValue: 'https://YOUR-PROJECT.vercel.app');
const String kAiProxyToken = String.fromEnvironment('AI_PROXY_TOKEN', defaultValue: '');
