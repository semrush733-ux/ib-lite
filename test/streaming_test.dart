import 'package:b1gtv/streaming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('streaming boxes: names', () {
    test('names become lower case letters and digits', () {
      expect(normName('Spider-Man: No Way Home'), 'spider man no way home');
      expect(normName('Café Society'), 'cafe society');
      expect(normName('Fast & Furious'), 'fast and furious');
      expect(normName('  '), '');
    });

    test('playlist titles lose their tags, the year is kept', () {
      final a = streamTitle('EN | Big Film (2024) [4K]');
      expect(normName(a.title), 'big film');
      expect(a.year, '2024');
      final b = streamTitle('|NF| Dark (2017) S01');
      expect(normName(b.title), 'dark');
      expect(b.year, '2017');
      expect(normName(streamTitle('Blade Runner 2049').title), 'blade runner 2049');
    });

    test('a category belongs to a service by whole words', () {
      final netflix = kStreamingServices.firstWhere((s) => s.id == 'netflix');
      final prime = kStreamingServices.firstWhere((s) => s.id == 'prime');
      final hbo = kStreamingServices.firstWhere((s) => s.id == 'hbo');
      expect(categoryIsFor('NETFLIX SERIES', netflix), true);
      expect(categoryIsFor('EN | Netflix Movies', netflix), true);
      expect(categoryIsFor('AMAZON PRIME', prime), true);
      expect(categoryIsFor('Primetime TV', prime), false);
      expect(categoryIsFor('HBO MAX', hbo), true);
      expect(categoryIsFor('Action', hbo), false);
    });
  });
}
