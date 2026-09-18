import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';
import 'join_course_screen.dart';
import 'exam_taking_screen.dart';
import 'results_screen.dart';

class StudentDashboard extends StatefulWidget {
  final String name;
  const StudentDashboard({super.key, required this.name});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  String _matricNumber = '';
  bool _isLoadingProfile = true;
  List<Map<String, dynamic>> _myCourses = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _availableExams = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoadingProfile = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        _matricNumber =
            userDoc.data()?['matricNumber']?.toString() ?? '';
      }

      final requestsSnapshot = await FirebaseFirestore.instance
          .collection('course_requests')
          .where('studentId', isEqualTo: user.uid)
          .get();

      final approved = <Map<String, dynamic>>[];
      final pending = <Map<String, dynamic>>[];
      final approvedCourseIds = <String>[];

      for (final doc in requestsSnapshot.docs) {
        final data = doc.data();
        final status = data['status']?.toString();
        if (status == 'approved') {
          approved.add({...data, 'requestId': doc.id});
          final courseId = data['courseId']?.toString();
          if (courseId != null && courseId.isNotEmpty) {
            approvedCourseIds.add(courseId);
          }
        } else if (status == 'pending') {
          pending.add({...data, 'requestId': doc.id});
        }
      }

      final exams = <Map<String, dynamic>>[];
      for (final courseId in approvedCourseIds) {
        final examSnapshot = await FirebaseFirestore.instance
            .collection('exams')
            .where('courseId', isEqualTo: courseId)
            .get();
        for (var doc in examSnapshot.docs) {
          final data = doc.data();
          data['examId'] = doc.id;
          exams.add(data);
        }
      }

      if (mounted) {
        setState(() {
          _myCourses = approved;
          _pendingRequests = pending;
          _availableExams = exams;
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  Future<void> _goToJoinCourse() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JoinCourseScreen(
          studentName: widget.name,
          matricNumber: _matricNumber,
        ),
      ),
    );
    _loadData();
  }

  Widget _buildSummaryCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding:
        const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: const Text('Student Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Notifications coming soon')),
              );
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration:
              const BoxDecoration(color: Color(0xFF1565C0)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person,
                        color: Color(0xFF1565C0), size: 30),
                  ),
                  const SizedBox(height: 10),
                  Text(widget.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  if (_matricNumber.isNotEmpty)
                    Text(_matricNumber,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard,
                  color: Color(0xFF1565C0)),
              title: const Text('Dashboard'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.school,
                  color: Color(0xFF1565C0)),
              title: const Text('My Courses'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.group_add,
                  color: Color(0xFF1565C0)),
              title: const Text('Join Course'),
              onTap: () {
                Navigator.pop(context);
                _goToJoinCourse();
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart,
                  color: Color(0xFF1565C0)),
              title: const Text('My Results'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ResultsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined,
                  color: Color(0xFF1565C0)),
              title: const Text('Notifications'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Notifications coming soon')),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout',
                  style: TextStyle(color: Colors.red)),
              onTap: _logout,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: _isLoadingProfile
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // PROFILE CARD
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 32,
                        backgroundColor: Color(0xFF1565C0),
                        child: Icon(Icons.person,
                            color: Colors.white, size: 30),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(widget.name,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1565C0))),
                            const SizedBox(height: 4),
                            if (_matricNumber.isNotEmpty)
                              Text(
                                'Matric No: $_matricNumber',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Are you ready for your next exam?',
                  style: TextStyle(
                      fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 20),

                // SUMMARY CARDS
                Row(
                  children: [
                    _buildSummaryCard(
                        'Courses',
                        '${_myCourses.length}',
                        Icons.school,
                        const Color(0xFF1565C0)),
                    const SizedBox(width: 10),
                    _buildSummaryCard(
                        'Exams',
                        '${_availableExams.length}',
                        Icons.assignment,
                        const Color(0xFF2E7D32)),
                    const SizedBox(width: 10),
                    _buildSummaryCard('Results', '0',
                        Icons.bar_chart,
                        const Color(0xFF6A1B9A)),
                    const SizedBox(width: 10),
                    _buildSummaryCard('Average', '—',
                        Icons.trending_up,
                        const Color(0xFFD84315)),
                  ],
                ),
                const SizedBox(height: 28),

                // QUICK ACTIONS
                const Text('Quick Actions',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.group_add),
                    label: const Text('Join Course'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(12)),
                    ),
                    onPressed: _goToJoinCourse,
                  ),
                ),
                const SizedBox(height: 28),

                // AVAILABLE EXAMS
                const Text('Available Exams',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _availableExams.isEmpty
                    ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                      BorderRadius.circular(12)),
                  child: Center(
                    child: Text(
                      'No exams available yet',
                      style: TextStyle(
                          color: Colors.grey.shade600),
                    ),
                  ),
                )
                    : Column(
                  children:
                  _availableExams.map((exam) {
                    return Container(
                      margin: const EdgeInsets.only(
                          bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                        BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding:
                            const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1565C0)
                                  .withValues(alpha: 0.1),
                              borderRadius:
                              BorderRadius.circular(10),
                            ),
                            child: const Icon(
                                Icons.quiz_outlined,
                                color: Color(0xFF1565C0)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(
                                  exam['title'] ??
                                      'Untitled Exam',
                                  style: const TextStyle(
                                      fontWeight:
                                      FontWeight.bold,
                                      fontSize: 15),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  exam['courseName'] ?? '',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors
                                          .grey.shade600),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.timer,
                                        size: 14,
                                        color: Colors.orange),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${exam['durationMinutes'] ?? 30} mins',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey
                                              .shade600),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(Icons.quiz,
                                        size: 14,
                                        color: Colors.green),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${(exam['questions'] as List?)?.length ?? 0} questions',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey
                                              .shade600),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ExamTakingScreen(
                                        examId:
                                        exam['examId'] ?? '',
                                        examTitle:
                                        exam['title'] ??
                                            'Exam',
                                        durationMinutes: exam[
                                        'durationMinutes'] ??
                                            30,
                                        questions:
                                        exam['questions'] ??
                                            [],
                                        courseId:
                                        exam['courseId'] ??
                                            '',
                                        courseName:
                                        exam['courseName'] ??
                                            '',
                                      ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                              const Color(0xFF1565C0),
                              foregroundColor: Colors.white,
                              padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8),
                            ),
                            child: const Text('Start',
                                style:
                                TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),

                // MY COURSES
                const Text('My Courses',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _myCourses.isEmpty
                    ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                      BorderRadius.circular(12)),
                  child: Center(
                    child: Text(
                        'You haven\'t joined any courses yet',
                        style: TextStyle(
                            color: Colors.grey.shade600)),
                  ),
                )
                    : Column(
                  children: _myCourses.map((course) {
                    return Container(
                      margin: const EdgeInsets.only(
                          bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                        BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Color(0xFF2E7D32)),
                          const SizedBox(width: 12),
                          Text(
                            course['courseName'] ??
                                'Unnamed Course',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),

                // PENDING REQUESTS
                const Text('Pending Requests',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _pendingRequests.isEmpty
                    ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                      BorderRadius.circular(12)),
                  child: Center(
                    child: Text('No pending requests',
                        style: TextStyle(
                            color: Colors.grey.shade600)),
                  ),
                )
                    : Column(
                  children:
                  _pendingRequests.map((req) {
                    return Container(
                      margin: const EdgeInsets.only(
                          bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                        BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.hourglass_top,
                              color: Colors.orange),
                          const SizedBox(width: 12),
                          Text(
                            req['courseName'] ??
                                'Unnamed Course',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}