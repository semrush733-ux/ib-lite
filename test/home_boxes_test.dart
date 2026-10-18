import 'package:b1gtv/screens/home.dart';
import 'package:b1gtv/xtream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bottomRow(Widget box) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 900,
            // Like the home screen: three boxes of the same height.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 300, child: ColoredBox(color: Colors.black)),
                  Expanded(child: box),
                  const SizedBox(width: 270),
                ],
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('playlist box: name, end date, days left and connections', (tester) async {
    final end = DateTime.now().add(const Duration(days: 89));
    await tester.pumpWidget(_bottomRow(PlaylistInfoBox(
      name: 'demo',
      account: XAccount(status: 'Active', expires: end, maxConnections: 2),
      offline: false,
      m3u: false,
    )));
    expect(find.text('Playlist: demo'), findsOneWidget);
    expect(find.textContaining('Playlist Expiry: '), findsOneWidget);
    expect(find.text('89 days left  ·  2 connections'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('playlist box: no end date, M3U and no connection', (tester) async {
    await tester.pumpWidget(_bottomRow(const PlaylistInfoBox(
      name: 'Home', account: XAccount(status: 'Active', maxConnections: 1), offline: false, m3u: false)));
    expect(find.text('Playlist Expiry: Unlimited'), findsOneWidget);
    expect(find.text('Active  ·  1 connection'), findsOneWidget);

    await tester.pumpWidget(_bottomRow(const PlaylistInfoBox(
      name: 'List', account: XAccount(status: 'Active', note: 'M3U playlist  ·  3 channels, 2 movies'), offline: false, m3u: true)));
    expect(find.text('3 channels, 2 movies'), findsOneWidget);

    await tester.pumpWidget(_bottomRow(const PlaylistInfoBox(name: 'Home', account: null, offline: true, m3u: false)));
    expect(find.text('No connection to the server'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
