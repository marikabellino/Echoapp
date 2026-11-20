import 'package:flutter/services.dart';
import 'package:echo/features/auth/presentation/widgets/birth_date_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseBirthDate accetta GG/MM/AAAA e rifiuta date inesistenti', () {
    expect(parseBirthDate('01/06/2009'), DateTime(2009, 6, 1));
    expect(parseBirthDate('31/02/2008'), isNull);
    expect(parseBirthDate('1/6/2009'), isNull);
  });

  test('ageOn conta gli anni compiuti', () {
    final today = DateTime(2026, 11, 20);
    expect(ageOn(DateTime(2010, 11, 20), today), 16);
    expect(ageOn(DateTime(2010, 11, 21), today), 15);
    expect(ageOn(DateTime(2008, 11, 19), today), 18);
  });

  test('validateBirthDate: minimo 16 anni', () {
    final now = DateTime.now();
    final fifteen = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year - 15}';
    final twenty = '01/01/${now.year - 20}';
    expect(validateBirthDate(fifteen, minAge: 16), isNotNull);
    expect(validateBirthDate(twenty, minAge: 16), isNull);
    expect(validateBirthDate('', minAge: 16), isNotNull);
  });

  test('il formatter aggiunge le barre', () {
    final f = BirthDateInputFormatter();
    final out = f.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: '12052008'),
    );
    expect(out.text, '12/05/2008');
  });
}
