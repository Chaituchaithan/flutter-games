import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/languages.dart';

void main() {
  test('API language values map to the picker list', () {
    expect(appLanguages[languageIndexFor('en')!].english, 'English');
    expect(appLanguages[languageIndexFor('es-ES')!].english, 'Spanish');
    expect(appLanguages[languageIndexFor('Hindi')!].code, 'hi');
    expect(languageIndexFor(null), isNull);
    expect(languageIndexFor('xx'), isNull);
  });
}
