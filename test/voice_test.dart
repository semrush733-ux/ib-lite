import 'package:b1gtv/logbook.dart';
import 'package:b1gtv/voice.dart';
import 'package:b1gtv/xtream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channels = [
    'UK: Sky Sports Main Event FHD',
    'UK: Sky Sports Football',
    'UK: Sky Sports 1',
    'UK: Sky Sports 10',
    'BBC One HD',
    'Geo News',
  ];

  group('what was said to the player', () {
    test('films and episodes', () {
      expect(parseVoice(['next episode'], live: false).action, 'next');
      expect(parseVoice(['previous'], live: false).action, 'previous');
      expect(parseVoice(['pause'], live: false).action, 'pause');
      expect(parseVoice(['stop'], live: false).action, 'pause');
      expect(parseVoice(['play'], live: false).action, 'play');
      expect(parseVoice(['resume'], live: false).action, 'play');
      expect(parseVoice(['start over'], live: false).action, 'startover');
      final back = parseVoice(['go back 30 seconds'], live: false);
      expect(back.action, 'back');
      expect(back.seconds, 30);
      final fwd = parseVoice(['forward two minutes'], live: false);
      expect(fwd.action, 'forward');
      expect(fwd.seconds, 120);
      expect(parseVoice(['rewind 5 minutes'], live: false).seconds, 300);
      expect(parseVoice(['skip 10 minutes'], live: false).seconds, 600);
      expect(parseVoice(['skip'], live: false).action, 'next');
      expect(parseVoice(['banana bread'], live: false).action, 'unknown');
    });

    test('live channels', () {
      final main = parseVoice(['Sky Sports Main Event'], live: true, channels: channels);
      expect(main.action, 'channel');
      expect(main.index, 0);
      expect(parseVoice(['play sky sports 1'], live: true, channels: channels).index, 2);
      expect(parseVoice(['BBC One'], live: true, channels: channels).index, 4);
      expect(parseVoice(['channel 6'], live: true, channels: channels).index, 5);
      expect(parseVoice(['next channel'], live: true, channels: channels).action, 'next');
      expect(parseVoice(['last channel'], live: true, channels: channels).action, 'last');
      expect(parseVoice(['previous channel'], live: true, channels: channels).action, 'last');
      expect(parseVoice(['shuru se'], live: true, channels: channels).action, 'startover');
      expect(parseVoice(['rewind'], live: true, channels: channels).action, 'back');
      expect(parseVoice(['cartoon network'], live: true, channels: channels).action, 'unknown');
      // The first guess that means something wins.
      expect(parseVoice(['geo noose', 'geo news'], live: true, channels: channels).index, 5);
    });

    test('voice search words', () {
      expect(voiceQuery('play Avengers Endgame movie'), 'avengers endgame');
      expect(voiceQuery('Breaking Bad season 2'), 'breaking bad 2');
      expect(voiceQuery('movie'), 'movie');
      expect(voiceNorm('शुरू से'), 'शुरू से');
    });
  });

  group('report log', () {
    test('addresses keep only the host, logins are masked', () {
      expect(LogBook.clean('open http://user:pass@line.example.com:8080/live/user/pass/1.ts now'),
          'open http://line.example.com:8080/… now');
      expect(LogBook.clean('GET /player_api.php?username=bob&password=secret'),
          'GET /player_api.php?username=***&password=***');
      expect(LogBook.clean('plain line'), 'plain line');
    });
  });

  group('films: year and date', () {
    test('year from the server or the name', () {
      expect(yearOf({'year': '2021'}, 'X'), 2021);
      expect(yearOf({'releaseDate': '2019-05-02'}, 'X'), 2019);
      expect(yearOf(const {}, 'Dune: Part Two (2024)'), 2024);
      expect(yearOf(const {}, 'Movie - 2018'), 2018);
      expect(yearOf(const {}, 'Blade Runner 2049'), 0);
      final item = XItem.fromApi(XKind.vod, {'stream_id': 7, 'name': 'Film (2020)', 'added': '1700000000', 'rating': '7,5'})!;
      expect(item.added, 1700000000);
      expect(item.year, 2020);
      expect(item.ratingValue, 7.5);
      final copy = XItem.fromJson(item.toJson())!;
      expect(copy.added, 1700000000);
      expect(copy.year, 2020);
    });
  });
}
