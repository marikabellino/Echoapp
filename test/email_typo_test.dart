import 'package:flutter_test/flutter_test.dart';
import 'package:echo/features/auth/presentation/widgets/email_typo.dart';

void main() {
  test('corregge gli errori più comuni', () {
    expect(suggestEmailFix('anna@gmial.com'), 'anna@gmail.com');
    expect(suggestEmailFix('anna@gmail.con'), 'anna@gmail.com');
    expect(suggestEmailFix('Anna@Hotmial.it'), 'anna@hotmail.it');
    expect(suggestEmailFix('anna@hotmal.com'), 'anna@hotmail.com');
    expect(suggestEmailFix('anna@icloud.co'), 'anna@icloud.com');
    expect(suggestEmailFix('anna@yaho.it'), 'anna@yahoo.it');
    expect(suggestEmailFix('anna@outlok.com'), 'anna@outlook.com');
  });

  test('lascia stare gli indirizzi giusti e i domini sconosciuti', () {
    expect(suggestEmailFix('anna@gmail.com'), isNull);
    expect(suggestEmailFix('anna@hotmail.it'), isNull);
    expect(suggestEmailFix('anna@unipa.it'), isNull);
    expect(suggestEmailFix('anna@mingletheapp.com'), isNull);
    expect(suggestEmailFix('anna@studenti.unict.it'), isNull);
    expect(suggestEmailFix('non-una-email'), isNull);
  });
}
