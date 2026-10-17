import 'dart:convert';

import 'package:flutter/material.dart';

import 'store.dart';

/// One person who watches on this TV. Each profile has its own favourites, recently watched,
/// resume positions and Continue Watching. A Kids profile shows only categories for children.
class Profile {
  const Profile({required this.id, required this.name, this.color = 0, this.kids = false});

  final String id;
  final String name;
  final int color;
  final bool kids;

  Profile copyWith({String? name, int? color, bool? kids}) =>
      Profile(id: id, name: name ?? this.name, color: color ?? this.color, kids: kids ?? this.kids);

  Map<String, dynamic> toJson() => {'id': id, 'n': name, 'c': color, if (kids) 'k': 1};

  static Profile? fromJson(dynamic j) {
    if (j is! Map) return null;
    final id = (j['id'] ?? '').toString();
    if (id.isEmpty) return null;
    final name = (j['n'] ?? '').toString().trim();
    return Profile(
      id: id,
      name: name.isEmpty ? 'Profile' : name,
      color: int.tryParse('${j['c'] ?? 0}') ?? 0,
      kids: '${j['k'] ?? ''}' == '1',
    );
  }

  /// The first letter, for the round picture.
  String get initial {
    final n = name.trim();
    return n.isEmpty ? '?' : n.substring(0, 1).toUpperCase();
  }
}

/// The profiles of this TV. Without any saved, there is one: "Main".
class Profiles {
  Profiles._();

  static const maxCount = 6;

  /// Colours of the round profile pictures.
  static const colors = [
    Color(0xFFE3262F),
    Color(0xFF1E88FF),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFFD946EF),
    Color(0xFF14B8A6),
    Color(0xFF8B5CF6),
    Color(0xFFF97316),
  ];

  static Color colorOf(Profile p) => colors[p.color.abs() % colors.length];

  static const _main = Profile(id: 'main', name: 'Main');

  static List<Profile> get all {
    final list = <Profile>[];
    try {
      final data = jsonDecode(Store.profilesJson.isEmpty ? '[]' : Store.profilesJson);
      if (data is List) {
        for (final j in data) {
          final p = Profile.fromJson(j);
          if (p != null && !list.any((x) => x.id == p.id)) list.add(p);
        }
      }
    } catch (_) {}
    // The main profile is always there, always first.
    final main = list.where((p) => p.id == 'main').firstOrNull ?? _main;
    return [main, ...list.where((p) => p.id != 'main')];
  }

  static Profile get active {
    final id = Store.profileId;
    final list = all;
    return list.where((p) => p.id == id).firstOrNull ?? list.first;
  }

  static bool get several => all.length > 1;

  /// "Who's watching?" when the app starts.
  static bool get askNow => several && Store.askProfileAtStart;

  static Future<void> _save(List<Profile> list) =>
      Store.setProfilesJson(jsonEncode([for (final p in list) p.toJson()]));

  /// Uses [p] from now on (its own lists; a Kids profile shows only categories for children).
  static Future<void> use(Profile p) => Store.setProfile(p.id, kids: p.kids);

  static Future<Profile> add({required String name, required int color, required bool kids}) async {
    final p = Profile(id: 'p${DateTime.now().millisecondsSinceEpoch}', name: name.trim(), color: color, kids: kids);
    await _save([...all, p]);
    return p;
  }

  static Future<void> update(Profile p) async {
    await _save([for (final x in all) x.id == p.id ? p : x]);
    // The profile in use changed to / from Kids: the rule applies at once.
    if (p.id == Store.profileId) await Store.setProfile(p.id, kids: p.kids);
  }

  static Future<void> delete(Profile p) async {
    if (p.id == 'main') return;
    await _save([for (final x in all) if (x.id != p.id) x]);
    await Store.deleteProfileData(p.id);
    if (Store.profileId == p.id) await use(all.first);
  }
}

/// The round profile picture: the profile's colour with its first letter (a smiley for Kids).
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(this.profile, {super.key, this.size = 40});

  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Profiles.colorOf(profile);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.alphaBlend(const Color(0x33FFFFFF), c), Color.alphaBlend(const Color(0x55000000), c)],
        ),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: size * 0.3)],
      ),
      child: profile.kids
          ? Icon(Icons.child_care_rounded, color: Colors.white, size: size * 0.6)
          : Text(
              profile.initial,
              style: TextStyle(fontSize: size * 0.46, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1),
            ),
    );
  }
}
