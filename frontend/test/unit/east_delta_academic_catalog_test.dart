import 'package:flutter_test/flutter_test.dart';
import 'package:skillbridge_mobile/data/east_delta_academic_catalog.dart';

void main() {
  test('provides unique programs grouped under a department', () {
    final programs = eastDeltaProgramsByDepartment.values
        .expand((departmentPrograms) => departmentPrograms)
        .toList();

    expect(programs, hasLength(14));
    expect(programs.toSet(), hasLength(programs.length));
    expect(
      eastDeltaProgramsByDepartment['Computer Science & Engineering'],
      contains(
        'BACHELOR OF SCIENCE IN COMPUTER SCIENCE & ENGINEERING (B.SC. IN CSE)',
      ),
    );
  });
}
