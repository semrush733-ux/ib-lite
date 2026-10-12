import 'package:flutter/material.dart';

import 'backend.dart';
import 'm3u.dart';
import 'config.dart';
import 'screens/connect.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'store.dart';
import 'xtream.dart';

/// The app's one navigator, so the licence check and the update notice can reach the screen
/// from anywhere.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// The screen the app opens on: home with the saved playlist, or the QR screen.
Widget startScreen() {
  // No sign-in form: the playlist is added on the website (QR code). Only the automated
  // emulator test, which has no website, still signs in with the old form.
  if (!Store.loggedIn) return kPrefillServer.isNotEmpty ? const LoginScreen() : const ConnectScreen();
  if (Store.isM3u) return HomeScreen(api: M3uSource(Store.m3uUrl, epgUrl: Store.m3uEpgUrl));
  var server = Store.server;
  // A customer who signed in with username and password only follows the website: when the
  // server address is changed there, the app uses the new one from its next start.
  if (Store.viaSite && Backend.serverUrl.isNotEmpty && bareServer(Backend.serverUrl) != bareServer(server)) {
    final moved = parseServerInput(Backend.serverUrl).server;
    if (moved.isNotEmpty) {
      server = moved;
      Store.moveServer(moved);
    }
  }
  return HomeScreen(api: XtreamApi(server, Store.username, Store.password));
}
