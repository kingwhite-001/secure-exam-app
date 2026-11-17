import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

class ImportedQuestion {
  final String question;
  final String a;
  final String b;
  final String c;
  final String d;
  final String answer;

  const ImportedQuestion({
    required this.question,
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.answer,
  });
}

class QuestionImport {
  final List<ImportedQuestion> questions;
  final int skipped;
  final List<String> headers;

  const QuestionImport(this.questions, this.skipped, this.headers);
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Reads a CSV file (comma, semicolon or tab separated) into rows of text.
List<List<String>> parseCsv(String input) {
  var text = input;
  if (text.startsWith('\uFEFF')) text = text.substring(1);

  final nl = text.indexOf('\n');
  final head = nl == -1 ? text : text.substring(0, nl);
  final commas = ','.allMatches(head).length;
  final semis = ';'.allMatches(head).length;
  final tabs = '\t'.allMatches(head).length;
  var delimiter = ',';
  if (semis > commas && semis >= tabs) delimiter = ';';
  if (tabs > commas && tabs > semis) delimiter = '\t';

  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;

  void endRow() {
    row.add(cell.toString().trim());
    cell.clear();
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(ch);
      }
    } else {
      if (ch == '"') {
        inQuotes = true;
      } else if (ch == delimiter) {
        row.add(cell.toString().trim());
        cell.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        endRow();
      } else {
        cell.write(ch);
      }
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// Reads the first sheet of an .xlsx file into rows of text.
List<List<String>> rowsFromXlsx(Uint8List bytes) {
  try {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return [];
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null) return [];
    final out = <List<String>>[];
    for (var i = 0; i < sheet.maxRows; i++) {
      final cells = sheet
          .row(i)
          .map((c) => c?.value?.toString().trim() ?? '')
          .toList();
      if (cells.any((c) => c.isNotEmpty)) out.add(cells);
    }
    return out;
  } catch (_) {
    throw const FormatException('XLSX_UNREADABLE');
  }
}

/// Finds the columns from the headings in row 1 and builds the questions.
QuestionImport buildQuestions(List<List<String>> rows) {
  if (rows.isEmpty) return const QuestionImport([], 0, []);

  final rawHeaders = rows.first;
  final headers = rawHeaders.map(_norm).toList();

  int find(List<String> names) => headers.indexWhere((h) => names.contains(h));

  var qCol = find(['question', 'questions', 'questiontext', 'questiontitle']);
  if (qCol == -1) {
    qCol = headers.indexWhere((h) =>
    h.contains('question') &&
        !h.contains('no') &&
        !h.contains('num') &&
        !h.contains('id'));
  }
  var aCol = find(['a', 'optiona', 'choicea', 'opta']);
  var bCol = find(['b', 'optionb', 'choiceb', 'optb']);
  var cCol = find(['c', 'optionc', 'choicec', 'optc']);
  var dCol = find(['d', 'optiond', 'choiced', 'optd']);
  var ansCol = find([
    'correctanswer',
    'correctoption',
    'correct',
    'answer',
    'ans',
    'key',
    'correctans',
    'rightanswer',
  ]);
  if (ansCol == -1) {
    ansCol = headers.indexWhere((h) => h.contains('correct'));
  }

  if (qCol == -1 ||
      aCol == -1 ||
      bCol == -1 ||
      cCol == -1 ||
      dCol == -1 ||
      ansCol == -1) {
    // Headings not recognised: go by position, skipping a leading
    // serial-number column if there is one.
    const serial = [
      '',
      'sn',
      'sno',
      's',
      'no',
      'num',
      'number',
      'id',
      'qno',
      'serialno',
      'serialnumber',
      'questionno',
      'questionnumber',
    ];
    final base = (headers.isNotEmpty && serial.contains(headers.first)) ? 1 : 0;
    qCol = base;
    aCol = base + 1;
    bCol = base + 2;
    cCol = base + 3;
    dCol = base + 4;
    ansCol = base + 5;
  }

  final validAnswer = RegExp(r'^[ABCD][\.\)]?$');
  String cell(List<String> row, int i) =>
      (i < 0 || i >= row.length) ? '' : row[i].trim();

  final out = <ImportedQuestion>[];
  var skipped = 0;
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    final text = cell(row, qCol);
    if (text.isEmpty) continue;

    final answer = cell(row, ansCol).toUpperCase();
    if (!validAnswer.hasMatch(answer)) {
      skipped++;
      continue;
    }
    out.add(ImportedQuestion(
      question: text,
      a: cell(row, aCol),
      b: cell(row, bCol),
      c: cell(row, cCol),
      d: cell(row, dCol),
      answer: answer[0],
    ));
  }

  return QuestionImport(
    out,
    skipped,
    rawHeaders.where((h) => h.isNotEmpty).toList(),
  );
}

QuestionImport importQuestionsFromFile(String fileName, Uint8List bytes) {
  final rows = fileName.toLowerCase().endsWith('.csv')
      ? parseCsv(utf8.decode(bytes, allowMalformed: true))
      : rowsFromXlsx(bytes);
  return buildQuestions(rows);
}