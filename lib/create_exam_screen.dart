import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class Question {
  final TextEditingController questionController = TextEditingController();
  final TextEditingController optionAController = TextEditingController();
  final TextEditingController optionBController = TextEditingController();
  final TextEditingController optionCController = TextEditingController();
  final TextEditingController optionDController = TextEditingController();
  String correctAnswer = 'A';
}

class CreateExamScreen extends StatefulWidget {
  const CreateExamScreen({super.key});

  @override
  State<CreateExamScreen> createState() => _CreateExamScreenState();
}

class _CreateExamScreenState extends State<CreateExamScreen> {
  final _titleController = TextEditingController();
  final _durationController = TextEditingController();
  final List<Question> _questions = [Question()];
  bool _isSaving = false;
  bool _isImporting = false;
  String _examType = 'Exam';

  // Course selection
  List<Map<String, dynamic>> _courses = [];
  String? _selectedCourseId;
  String? _selectedCourseName;
  bool _isLoadingCourses = true;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('courses')
          .where('lecturerId', isEqualTo: user.uid)
          .get();

      final courses = snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'name': doc.data()['name'] ?? 'Unnamed Course',
          'joinCode': doc.data()['joinCode'] ?? '',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _courses = courses;
          _isLoadingCourses = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCourses = false);
      }
    }
  }

  void _showMessage(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _addQuestion() {
    setState(() {
      _questions.add(Question());
    });
  }

  void _removeQuestion(int index) {
    if (_questions.length > 1) {
      setState(() {
        _questions.removeAt(index);
      });
    }
  }

  // ---------------- EXCEL IMPORT ----------------
  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  String _cell(List<Data?> row, int i) {
    if (i < 0 || i >= row.length) return '';
    return row[i]?.value?.toString().trim() ?? '';
  }

  Future<void> _importFromExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null) return;

      final bytes = result.files.single.bytes;
      if (bytes == null) {
        _showMessage(
            'Could not read that file. Try again, or move it into your phone storage first.');
        return;
      }

      setState(() => _isImporting = true);

      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null || sheet.maxRows < 2) {
        _showMessage(
            'The spreadsheet looks empty. Row 1 must hold the headings and the questions start in row 2.');
        return;
      }

      // Work out which column holds what, using the headings in row 1.
      final headers =
      sheet.row(0).map((c) => _norm(c?.value?.toString() ?? '')).toList();

      int find(List<String> names) =>
          headers.indexWhere((h) => names.contains(h));

      var qCol =
      find(['question', 'questions', 'questiontext', 'questiontitle']);
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
        final base =
        (headers.isNotEmpty && serial.contains(headers.first)) ? 1 : 0;
        qCol = base;
        aCol = base + 1;
        bCol = base + 2;
        cCol = base + 3;
        dCol = base + 4;
        ansCol = base + 5;
      }

      final validAnswer = RegExp(r'^[ABCD][\.\)]?$');
      final imported = <Question>[];
      var skipped = 0;

      for (var i = 1; i < sheet.maxRows; i++) {
        final row = sheet.row(i);
        final text = _cell(row, qCol);
        if (text.isEmpty) continue;

        final answer = _cell(row, ansCol).toUpperCase();
        if (!validAnswer.hasMatch(answer)) {
          skipped++;
          continue;
        }

        final q = Question();
        q.questionController.text = text;
        q.optionAController.text = _cell(row, aCol);
        q.optionBController.text = _cell(row, bCol);
        q.optionCController.text = _cell(row, cCol);
        q.optionDController.text = _cell(row, dCol);
        q.correctAnswer = answer[0];
        imported.add(q);
      }

      if (imported.isEmpty) {
        final found = headers.where((h) => h.isNotEmpty).join(', ');
        _showMessage(
          'No valid questions found. Headings I found: $found. '
              'Expected: Question, A, B, C, D, Correct Answer (a single letter A to D).',
        );
        return;
      }

      setState(() {
        _questions.clear();
        _questions.addAll(imported);
      });

      _showMessage(
        '${imported.length} questions imported.'
            '${skipped > 0 ? ' $skipped row(s) skipped because Correct Answer was not A, B, C or D.' : ''}'
            ' Please review them before publishing.',
        color: Colors.green,
      );
    } catch (e) {
      _showMessage('Import failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  // ---------------- SAVE ----------------
  Future<void> _saveExam() async {
    if (_selectedCourseId == null) {
      _showMessage('Please select a course for this exam');
      return;
    }

    if (_titleController.text.isEmpty || _durationController.text.isEmpty) {
      _showMessage('Please enter exam title and duration');
      return;
    }

    for (var q in _questions) {
      if (q.questionController.text.isEmpty ||
          q.optionAController.text.isEmpty ||
          q.optionBController.text.isEmpty ||
          q.optionCController.text.isEmpty ||
          q.optionDController.text.isEmpty) {
        _showMessage('Please fill in all question fields');
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      final questionsData = _questions.map((q) {
        return {
          'question': q.questionController.text.trim(),
          'optionA': q.optionAController.text.trim(),
          'optionB': q.optionBController.text.trim(),
          'optionC': q.optionCController.text.trim(),
          'optionD': q.optionDController.text.trim(),
          'correctAnswer': q.correctAnswer,
        };
      }).toList();

      await FirebaseFirestore.instance.collection('exams').add({
        'title': _titleController.text.trim(),
        'durationMinutes': int.tryParse(_durationController.text.trim()) ?? 30,
        'createdBy': user?.uid,
        'createdAt': DateTime.now().toIso8601String(),
        'questions': questionsData,
        'courseId': _selectedCourseId,
        'courseName': _selectedCourseName,
        'examType': _examType,
      });

      if (mounted) {
        _showMessage('Exam created successfully!', color: Colors.green);
        Navigator.pop(context);
      }
    } catch (e) {
      _showMessage('Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: const Text('Create Exam'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Course',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _isLoadingCourses
                  ? const Center(child: CircularProgressIndicator())
                  : _courses.isEmpty
                  ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You have no courses yet. Please create a course first before adding an exam.',
                      ),
                    ),
                  ],
                ),
              )
                  : Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text('Choose a course'),
                    value: _selectedCourseId,
                    items: _courses.map((course) {
                      return DropdownMenuItem<String>(
                        value: course['id'] as String,
                        child: Text(
                          '${course['name']} (${course['joinCode']})',
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCourseId = value;
                        final match = _courses.firstWhere(
                              (c) => c['id'] == value,
                        );
                        _selectedCourseName = match['name'] as String;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Exam Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Exam Title',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Duration (minutes)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Assessment Type',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: [
                  for (final type in ['CA', 'Exam'])
                    ChoiceChip(
                      label: Text(
                        type == 'CA' ? 'CA (Continuous Assessment)' : 'Final Exam',
                      ),
                      selected: _examType == type,
                      selectedColor: const Color(0xFF1565C0),
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color:
                        _examType == type ? Colors.white : Colors.black87,
                      ),
                      onSelected: (_) => setState(() => _examType = type),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1565C0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.upload_file, color: Color(0xFF1565C0)),
                        SizedBox(width: 8),
                        Text(
                          'Bulk Upload Questions',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Row 1 = headings: Question | A | B | C | D | Correct Answer. '
                          'Questions start in row 2. Correct Answer must be a single letter (A to D). '
                          'An extra number column on the left is fine.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isImporting ? null : _importFromExcel,
                        icon: _isImporting
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                          CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Icon(Icons.file_upload_outlined),
                        label: Text(_isImporting
                            ? 'Importing...'
                            : 'Upload Excel File (.xlsx)'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Questions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...List.generate(_questions.length, (index) {
                final q = _questions[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Question ${index + 1}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          if (_questions.length > 1)
                            IconButton(
                              icon:
                              const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removeQuestion(index),
                            ),
                        ],
                      ),
                      TextField(
                        controller: q.questionController,
                        decoration: InputDecoration(
                          labelText: 'Question text',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: q.optionAController,
                        decoration: InputDecoration(
                          labelText: 'Option A',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: q.optionBController,
                        decoration: InputDecoration(
                          labelText: 'Option B',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: q.optionCController,
                        decoration: InputDecoration(
                          labelText: 'Option C',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: q.optionDController,
                        decoration: InputDecoration(
                          labelText: 'Option D',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Correct Answer',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: ['A', 'B', 'C', 'D'].map((letter) {
                          final isSelected = q.correctAnswer == letter;
                          return GestureDetector(
                            onTap: () {
                              setState(() => q.correctAnswer = letter);
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF1565C0)
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  letter,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addQuestion,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Another Question'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveExam,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                    'Publish Exam',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}