import 'dart:io';

import 'package:excel/excel.dart';

/// خدمة مساعدة لقراءة ورقة الكشوفات الرسمية statment.
class ExcelService {
  final String path;
  late final Excel _excel;
  late final Sheet _sheet;

  ExcelService(this.path) {
    final bytes = File(path).readAsBytesSync();
    _excel = Excel.decodeBytes(bytes);
    final sheet = _excel.tables['statment'];
    if (sheet == null) {
      throw Exception('الملف لا يحتوي على ورقة statment.');
    }
    _sheet = sheet;
  }

  String _cellText(int column, int row) {
    final value = _sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
        .value;
    if (value == null) return '';
    if (value is TextCellValue) return value.value.text?.trim() ?? '';
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    return value.toString().trim();
  }

  int? findStudentBySecretCode(String secretCode) {
    final wanted = secretCode.trim();
    for (int row = 5; row < _sheet.maxRows; row++) {
      if (_cellText(3, row) == wanted) return row;
    }
    return null;
  }

  Future<void> updateGrade(
    int studentRow,
    String subjectName,
    String grade, {
    int columnOffset = 1,
  }) async {
    int subjectColumn = -1;
    for (int col = 4; col < _sheet.maxColumns; col += 5) {
      if (_cellText(col, 2) == subjectName.trim()) {
        subjectColumn = col;
        break;
      }
    }
    if (subjectColumn < 0) {
      throw Exception('لم يتم العثور على المادة في الصف الثالث من statment.');
    }
    final targetColumn = subjectColumn + columnOffset;
    _sheet
        .cell(CellIndex.indexByColumnRow(
          columnIndex: targetColumn,
          rowIndex: studentRow,
        ))
        .value = TextCellValue(grade);
    final bytes = _excel.encode();
    if (bytes == null) throw Exception('تعذر إنشاء ملف Excel بعد تحديث الدرجة.');
    await File(path).writeAsBytes(bytes, flush: true);
  }

  List<String> getSubjects() {
    final subjects = <String>[];
    for (int col = 4; col < _sheet.maxColumns; col += 5) {
      final value = _cellText(col, 2);
      if (value.isNotEmpty && !value.contains('المجموع')) {
        subjects.add(value);
      }
    }
    return subjects;
  }
}
