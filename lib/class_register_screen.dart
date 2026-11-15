import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _ExamMark {
  final String title;
  final String type;
  final int percentage;
  final int score;
  final int total;
  final int strikes;
  final bool terminated;
  final List<String> flags;

  const _ExamMark({
    required this.title,
    required this.type,
    required this.percentage,
    required this.score,
    required this.total,
    required this.strikes,
    required this.terminated,
    required this.flags,
  });
}

class _StudentRow {
  final String studentId;
  final String name;
  final String matric;
  final List<_ExamMark> marks = [];

  _StudentRow(this.studentId, this.name, this.matric);

  double? _average({required bool ca}) {
    final list = marks.where((m) => (m.type == 'CA') == ca).toList();
    if (list.isEmpty) return null;
    final sum = list.fold<int>(0, (s, m) => s + m.percentage);
    return sum / list.length;
  }

  double? get caAverage => _average(ca: true);
  double? get examAverage => _average(ca: false);
  int get totalStrikes => marks.fold<int>(0, (s, m) => s + m.strikes);
}

class ClassRegisterScreen extends StatefulWidget {
  const ClassRegisterScreen({super.key});

  @override
  State<ClassRegisterScreen> createState() => _ClassRegisterScreenState();
}

class _ClassRegisterScreenState extends State<ClassRegisterScreen> {
  List<Map<String, dynamic>> _courses = [];
  String? _courseId;
  List<_StudentRow> _rows = [];
  int _caCount = 0;
  int _examCount = 0;
  bool _loadingCourses = true;
  bool _loadingRegister = false;

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
        _loadingCourses = false;
        if (courses.isNotEmpty) _courseId = courses.first['id'] as String;
      });
      if (courses.isNotEmpty) await _loadRegister();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCourses = false);
      _toast('Could not load courses: $e');
    }
  }

  Future<void> _loadRegister() async {
    final courseId = _courseId;
    if (courseId == null) return;
    setState(() => _loadingRegister = true);

    try {
      final db = FirebaseFirestore.instance;
      final snaps = await Future.wait([
        db
            .collection('course_requests')
            .where('courseId', isEqualTo: courseId)
            .where('status', isEqualTo: 'approved')
            .get(),
        db.collection('exams').where('courseId', isEqualTo: courseId).get(),
        db
            .collection('exam_results')
            .where('courseId', isEqualTo: courseId)
            .get(),
      ]);
      final students = snaps[0];
      final exams = snaps[1];
      final results = snaps[2];

      // examId -> CA or Exam (older exams without a type count as Exam)
      final examType = <String, String>{};
      var ca = 0;
      var ex = 0;
      for (final d in exams.docs) {
        final t = (d.data()['examType'] ?? 'Exam').toString();
        examType[d.id] = t;
        if (t == 'CA') {
          ca++;
        } else {
          ex++;
        }
      }

      final byStudent = <String, _StudentRow>{};
      for (final d in students.docs) {
        final data = d.data();
        final id = (data['studentId'] ?? '').toString();
        if (id.isEmpty || byStudent.containsKey(id)) continue;
        byStudent[id] = _StudentRow(
          id,
          (data['studentName'] ?? 'Unknown').toString(),
          (data['matricNumber'] ?? '').toString(),
        );
      }

      for (final d in results.docs) {
        final data = d.data();
        final row = byStudent[(data['studentId'] ?? '').toString()];
        if (row == null) continue;
        final examId = (data['examId'] ?? '').toString();
        row.marks.add(_ExamMark(
          title: (data['examTitle'] ?? 'Exam').toString(),
          type: examType[examId] ?? 'Exam',
          percentage: (data['percentage'] as num?)?.toInt() ?? 0,
          score: (data['score'] as num?)?.toInt() ?? 0,
          total: (data['total'] as num?)?.toInt() ?? 0,
          strikes: (data['strikes'] as num?)?.toInt() ?? 0,
          terminated: data['terminatedForViolations'] == true,
          flags: ((data['flags'] as List?) ?? [])
              .map((e) => e.toString())
              .toList(),
        ));
      }

      final rows = byStudent.values.toList()
        ..sort((a, b) =>
            a.matric.toLowerCase().compareTo(b.matric.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _caCount = ca;
        _examCount = ex;
        _loadingRegister = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingRegister = false);
      _toast('Could not load the register: $e');
    }
  }

  String _fmt(double? v) => v == null ? '—' : '${v.round()}%';
  String _plain(double? v) => v == null ? '' : v.round().toString();

  void _copyTable() {
    final b = StringBuffer('No\tName\tMatric No\tCA (%)\tExam (%)\tWarnings\n');
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      b.writeln(
          '${i + 1}\t${r.name}\t${r.matric}\t${_plain(r.caAverage)}\t${_plain(r.examAverage)}\t${r.totalStrikes}');
    }
    Clipboard.setData(ClipboardData(text: b.toString()));
    _toast('Register copied. Paste it into Excel or Google Sheets.');
  }

  Widget _badge(String label, double? value, Color color) {
    final has = value != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: has ? color.withValues(alpha: 0.12) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
          const SizedBox(height: 2),
          Text(
            _fmt(value),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: has ? color : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 70, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  void _showDetails(_StudentRow r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(r.matric.isEmpty ? 'No matric number' : r.matric,
                    style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 14),
                if (r.marks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text('No exams taken yet.',
                        style: TextStyle(color: Colors.grey.shade600)),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: r.marks.map((m) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(m.title,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: m.type == 'CA'
                                          ? const Color(0xFFE3F2FD)
                                          : const Color(0xFFE8F5E9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      m.type == 'CA' ? 'CA' : 'Exam',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Score: ${m.score}/${m.total} (${m.percentage}%)',
                                style: const TextStyle(fontSize: 13),
                              ),
                              if (m.strikes > 0) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${m.strikes} warning(s): ${m.flags.join(', ')}'
                                      '${m.terminated ? '  (auto-submitted)' : ''}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade800),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Class Register'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Copy for Excel',
            icon: const Icon(Icons.copy_all),
            onPressed: _rows.isEmpty ? null : _copyTable,
          ),
        ],
      ),
      body: _loadingCourses
          ? const Center(child: CircularProgressIndicator())
          : _courses.isEmpty
          ? _emptyState(Icons.school_outlined, 'Create a course first')
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
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
                  value: _courseId,
                  items: _courses
                      .map((c) => DropdownMenuItem<String>(
                    value: c['id'] as String,
                    child: Text(c['name'].toString()),
                  ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _courseId = v);
                    _loadRegister();
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_rows.length} students  •  $_caCount CA  •  $_examCount Exam',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
          ),
          Expanded(
            child: _loadingRegister
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _loadRegister,
              child: _rows.isEmpty
                  ? ListView(
                physics:
                const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  _emptyState(Icons.people_outline,
                      'No approved students yet'),
                ],
              )
                  : ListView.builder(
                physics:
                const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                    16, 8, 16, 24),
                itemCount: _rows.length,
                itemBuilder: (context, i) {
                  final r = _rows[i];
                  return Card(
                    color: Colors.white,
                    surfaceTintColor: Colors.transparent,
                    elevation: 1,
                    margin:
                    const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius:
                      BorderRadius.circular(12),
                      onTap: () => _showDetails(r),
                      child: Padding(
                        padding:
                        const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor:
                              const Color(0xFFE3F2FD),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight:
                                  FontWeight.bold,
                                  color:
                                  Color(0xFF1565C0),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                                children: [
                                  Text(
                                    r.name,
                                    maxLines: 1,
                                    overflow: TextOverflow
                                        .ellipsis,
                                    style:
                                    const TextStyle(
                                        fontWeight:
                                        FontWeight
                                            .bold),
                                  ),
                                  const SizedBox(
                                      height: 2),
                                  Text(
                                    r.matric.isEmpty
                                        ? 'No matric number'
                                        : r.matric,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey
                                            .shade600),
                                  ),
                                  if (r.totalStrikes > 0)
                                    Padding(
                                      padding:
                                      const EdgeInsets
                                          .only(
                                          top: 4),
                                      child: Row(
                                        children: [
                                          const Icon(
                                              Icons
                                                  .warning_amber,
                                              size: 14,
                                              color: Colors
                                                  .orange),
                                          const SizedBox(
                                              width: 4),
                                          Text(
                                            '${r.totalStrikes} integrity warning(s)',
                                            style: TextStyle(
                                                fontSize:
                                                11,
                                                color: Colors
                                                    .orange
                                                    .shade800),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _badge('CA', r.caAverage,
                                const Color(0xFF1565C0)),
                            const SizedBox(width: 6),
                            _badge('Exam', r.examAverage,
                                const Color(0xFF2E7D32)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}