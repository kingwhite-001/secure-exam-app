import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ResetAttemptScreen extends StatefulWidget {
  const ResetAttemptScreen({super.key});

  @override
  State<ResetAttemptScreen> createState() => _ResetAttemptScreenState();
}

class _ResetAttemptScreenState extends State<ResetAttemptScreen> {
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _exams = [];
  List<Map<String, dynamic>> _students = [];
  final Set<String> _completed = {};
  String? _courseId;
  String? _examId;
  bool _loading = true;
  bool _loadingStudents = false;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadCourses() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snap = await FirebaseFirestore.instance
          .collection('courses')
          .where('lecturerId', isEqualTo: user.uid)
          .get();
      final courses = snap.docs
          .map<Map<String, dynamic>>((d) => {
        'id': d.id,
        'name': d.data()['name'] ?? 'Unnamed Course',
      })
          .toList();
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('Could not load courses: $e');
    }
  }

  Future<void> _pickCourse(String? id) async {
    if (id == null) return;
    setState(() {
      _courseId = id;
      _examId = null;
      _exams = [];
      _students = [];
      _completed.clear();
      _loadingStudents = true;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('exams')
          .where('courseId', isEqualTo: id)
          .get();
      final exams = snap.docs
          .map<Map<String, dynamic>>((d) => {
        'id': d.id,
        'title': d.data()['title'] ?? 'Untitled exam',
      })
          .toList();
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _loadingStudents = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingStudents = false);
      _toast('Could not load exams: $e');
    }
  }

  Future<void> _pickExam(String? id) async {
    final courseId = _courseId;
    final user = FirebaseAuth.instance.currentUser;
    if (id == null || courseId == null || user == null) return;

    setState(() {
      _examId = id;
      _loadingStudents = true;
      _completed.clear();
    });

    try {
      final db = FirebaseFirestore.instance;
      final reqs = await db
          .collection('course_requests')
          .where('courseId', isEqualTo: courseId)
          .where('lecturerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'approved')
          .get();
      final results = await db
          .collection('exam_results')
          .where('courseId', isEqualTo: courseId)
          .where('examId', isEqualTo: id)
          .get();

      final done =
      results.docs.map((d) => (d.data()['studentId'] ?? '').toString());

      final seen = <String>{};
      final students = <Map<String, dynamic>>[];
      for (final d in reqs.docs) {
        final data = d.data();
        final sid = (data['studentId'] ?? '').toString();
        if (sid.isEmpty || !seen.add(sid)) continue;
        students.add({
          'id': sid,
          'name': (data['studentName'] ?? 'Unknown').toString(),
          'matric': (data['matricNumber'] ?? '').toString(),
        });
      }
      students.sort(
              (a, b) => (a['matric'] as String).compareTo(b['matric'] as String));

      if (!mounted) return;
      setState(() {
        _students = students;
        _completed
          ..clear()
          ..addAll(done);
        _loadingStudents = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingStudents = false);
      _toast('Could not load students: $e');
    }
  }

  Future<void> _reset(Map<String, dynamic> student) async {
    final examId = _examId;
    if (examId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow another attempt?'),
        content: Text(
          '${student['name']} will be able to start this exam again. '
              'Only do this if their exam was interrupted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('exam_attempts')
          .doc('${student['id']}_$examId')
          .delete();
      _toast('Done. ${student['name']} can start this exam again.');
    } on FirebaseException catch (e) {
      _toast(e.code == 'permission-denied'
          ? 'Nothing to reset: this student has not started the exam.'
          : 'Could not reset: ${e.message}');
    } catch (e) {
      _toast('Could not reset: $e');
    }
  }

  Widget _dropdown({
    required String hint,
    required String? value,
    required List<Map<String, dynamic>> items,
    required String labelKey,
    required void Function(String?) onChanged,
  }) {
    return Container(
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
          hint: Text(hint),
          value: value,
          items: items
              .map((m) => DropdownMenuItem<String>(
            value: m['id'] as String,
            child: Text(
              m[labelKey].toString(),
              overflow: TextOverflow.ellipsis,
            ),
          ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _centerText(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Reset Exam Attempt'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _courses.isEmpty
          ? _centerText('Create a course first')
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _dropdown(
                  hint: 'Choose a course',
                  value: _courseId,
                  items: _courses,
                  labelKey: 'name',
                  onChanged: _pickCourse,
                ),
                const SizedBox(height: 10),
                _dropdown(
                  hint: 'Choose an exam',
                  value: _examId,
                  items: _exams,
                  labelKey: 'title',
                  onChanged: _pickExam,
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Use this when a student\'s phone died or the app crashed mid-exam. '
                        'Students who already submitted cannot be reset.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loadingStudents
                ? const Center(child: CircularProgressIndicator())
                : _examId == null
                ? _centerText('Choose a course and an exam')
                : _students.isEmpty
                ? _centerText('No approved students yet')
                : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  16, 0, 16, 24),
              itemCount: _students.length,
              itemBuilder: (context, i) {
                final s = _students[i];
                final done =
                _completed.contains(s['id']);
                final matric = s['matric'] as String;
                return Card(
                  color: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  elevation: 1,
                  margin:
                  const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(
                      s['name'] as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(matric.isEmpty
                        ? 'No matric number'
                        : matric),
                    trailing: done
                        ? Container(
                      padding: const EdgeInsets
                          .symmetric(
                          horizontal: 10,
                          vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(
                            0xFFE8F5E9),
                        borderRadius:
                        BorderRadius.circular(
                            12),
                      ),
                      child: const Text(
                        'Completed',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                          FontWeight.bold,
                          color:
                          Color(0xFF2E7D32),
                        ),
                      ),
                    )
                        : OutlinedButton(
                      onPressed: () =>
                          _reset(s),
                      child:
                      const Text('Reset'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}