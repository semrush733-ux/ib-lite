/// App-wide settings.
/// The app's name; the build sets it from brand/brand.txt.
const String kAppName = String.fromEnvironment('APP_NAME', defaultValue: 'Lite Player');

/// When the build sets a server address (config/server.txt), the login screen
/// hides the server field and customers only type username and password.
const String kLockedServer = String.fromEnvironment('B1G_SERVER');

/// Only used by the automated emulator test.
const String kPrefillServer = String.fromEnvironment('B1G_PREFILL_SERVER');
const String kPrefillUser = String.fromEnvironment('B1G_PREFILL_USER');
const String kPrefillPass = String.fromEnvironment('B1G_PREFILL_PASS');

/// Sent with every request, so the server can recognise the app.
const String kUserAgent = 'LitePlayer/1.0 (Android TV)';

/// Extra engine messages in the device log (test builds only).
const bool kVerbose = bool.fromEnvironment('B1G_VERBOSE');

/// Test builds: stay in the standard picture mode even when it cannot draw (the emulator has no
/// graphics chip), so the automated test can exercise every screen.
const bool kNoAutoDirect = bool.fromEnvironment('B1G_NO_AUTO_DIRECT');

/// TMDB (themoviedb.org) adds cast photos, stills and trailers to the movie details page.
/// The key comes from the build (repository secret TMDB_API_KEY); without it the page shows
/// only what the IPTV server itself knows.
const String kTmdbKey = String.fromEnvironment('B1G_TMDB_KEY');
const String kTmdbBase = String.fromEnvironment('B1G_TMDB_BASE', defaultValue: 'https://api.themoviedb.org/3');
const String kTmdbImages = String.fromEnvironment('B1G_TMDB_IMAGES', defaultValue: 'https://image.tmdb.org/t/p');

/// Samsung TV (Tizen) build: the web app packaged for the TV. It talks to IPTV servers directly
/// (no website relay) and the remote's Back / Exit keys work like on Android TV.
const bool kTizen = bool.fromEnvironment('B1G_TIZEN');

/// Which TV the packaged web app runs on ('samsung-tv' or 'lg-tv'), shown in the admin panel.
const String kTvPlatform = String.fromEnvironment('B1G_TV_PLATFORM', defaultValue: 'samsung-tv');

/// iPhone / iPad build: its build number and where it finds newer builds (set by the iPhone
/// workflow). The IPA cannot install itself; the app offers AltStore / SideStore (which then keep
/// it updated by themselves) or the new IPA.
const int kIosBuild = int.fromEnvironment('B1G_BUILD');
const String kIosFeed = String.fromEnvironment('B1G_IOS_FEED');

/// Google Play build: Play installs the updates (the app never downloads its own APK) and the
/// built-in VPN is left out (Play only allows VPN apps whose main job is the VPN).
const bool kPlay = bool.fromEnvironment('B1G_PLAY');

/// The website's privacy policy page (empty: <website>/privacy-policy-2/, see privacy.dart).
const String kPrivacyUrlBuild = String.fromEnvironment('B1G_PRIVACY_URL');
