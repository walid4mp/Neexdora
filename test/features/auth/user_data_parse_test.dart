import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/auth/data/models/user_data.dart';

void main() {
  Map<String, dynamic> row(Object? socialLinks) => {
    'id': 'u1',
    'name': 'Alice',
    'email': 'a@test.local',
    'social_links': socialLinks,
  };

  test('profile row with JSON object social_links parses', () {
    final u = UserData.fromMap(row({'github': 'https://github.com/x'}));
    expect(u.socialLinks['github'], 'https://github.com/x');
  });

  test('legacy [] / null social_links no longer crashes the Home screen', () {
    expect(UserData.fromMap(row(<dynamic>[])).socialLinks, isEmpty);
    expect(UserData.fromMap(row(null)).socialLinks, isEmpty);
  });
}
