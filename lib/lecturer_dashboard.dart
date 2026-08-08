import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'create_exam_screen.dart';
import 'create_course_screen.dart';
import 'edit_profile_screen.dart';
import 'pending_requests_screen.dart';
import 'main.dart';

class LecturerDashboard extends StatefulWidget {
  final String name;
  const LecturerDashboard({super.key, required this.name});

  @override
  State<LecturerDashboard> createState() => _LecturerDashboardState();
}

class _LecturerDashboardState extends State<LecturerDashboard> {
  String _institution = '';
  String _department = '';
  String _bio = '';
  int _avatarIndex = 0;
  bool _isLoadingProfile = true;
  int _coursesCount = 0;
  int _examsCount = 0;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (mounted) setState(() {
          _institution = data['institution'] ?? '';
          _department = data['department'] ?? '';
          _bio = data['bio'] ?? '';
          _avatarIndex = data['avatarIndex'] ?? 0;
        });
      }

      final courses = await FirebaseFirestore.instance
          .collection('courses')
          .where('lecturerId', isEqualTo: user.uid)
          .get();

      final exams = await FirebaseFirestore.instance
          .collection('exams')
          .where('createdBy', isEqualTo: user.uid)
          .get();

      final pending = await FirebaseFirestore.instance
          .collection('course_requests')
          .where('lecturerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (mounted) setState(() {
        _coursesCount = courses.docs.length;
        _examsCount = exams.docs.length;
        _pendingCount = pending.docs.length;
        _isLoadingProfile = false;
      });
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

  Future<void> _goToEditProfile() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const EditProfileScreen()));
    _loadAll();
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
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
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style:
                TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
        title: const Text('Lecturer Dashboard'),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF1565C0)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: avatarColors[_avatarIndex],
                    child: Icon(avatarIcons[_avatarIndex],
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 10),
                  Text(widget.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  Text(_department,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard, color: Color(0xFF1565C0)),
              title: const Text('Dashboard'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: Stack(
                children: [
                  const Icon(Icons.pending_actions, color: Color(0xFF1565C0)),
                  if (_pendingCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                        child: Text('$_pendingCount',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 9)),
                      ),
                    ),
                ],
              ),
              title: const Text('Pending Requests'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PendingRequestsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Color(0xFF1565C0)),
              title: const Text('Edit Profile'),
              onTap: () {
                Navigator.pop(context);
                _goToEditProfile();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title:
              const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: _logout,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: _isLoadingProfile
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: _loadAll,
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
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: avatarColors[_avatarIndex],
                        child: Icon(avatarIcons[_avatarIndex],
                            color: Colors.white, size: 34),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.name,
                                style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1565C0))),
                            const SizedBox(height: 4),
                            if (_institution.isNotEmpty)
                              Text(_institution,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700)),
                            if (_department.isNotEmpty)
                              Text(_department,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600)),
                            if (_bio.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(_bio,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey.shade600)),
                            ],
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: _goToEditProfile,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit,
                                      size: 14,
                                      color: Colors.blue.shade700),
                                  const SizedBox(width: 4),
                                  Text('Edit Profile',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue.shade700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // STATS CARDS
                Row(
                  children: [
                    _buildStatCard('Courses', '$_coursesCount',
                        Icons.school, const Color(0xFF1565C0)),
                    const SizedBox(width: 10),
                    _buildStatCard('Exams', '$_examsCount',
                        Icons.assignment, const Color(0xFF2E7D32)),
                    const SizedBox(width: 10),
                    _buildStatCard('Pending', '$_pendingCount',
                        Icons.pending_actions, Colors.orange),
                  ],
                ),
                const SizedBox(height: 24),

                const Text('Manage your examinations',
                    style:
                    TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 16),

                // BUTTONS
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CreateCourseScreen(
                                lecturerName: widget.name))),
                    icon: const Icon(Icons.school),
                    label: const Text('Create Course',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CreateExamScreen())),
                    icon: const Icon(Icons.add),
                    label: const Text('Create New Exam',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                            const PendingRequestsScreen())),
                    icon: Stack(
                      children: [
                        const Icon(Icons.pending_actions),
                        if (_pendingCount > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle),
                              child: Text('$_pendingCount',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9)),
                            ),
                          ),
                      ],
                    ),
                    label: const Text('Pending Requests',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // YOUR COURSES
                const Text('Your Courses',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('courses')
                      .where('lecturerId',
                      isEqualTo: FirebaseAuth
                          .instance.currentUser?.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData ||
                        snapshot.data!.docs.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12)),
                        child: Center(
                          child: Text('No courses created yet',
                              style: TextStyle(
                                  color: Colors.grey.shade600)),
                        ),
                      );
                    }
                    return Column(
                      children: snapshot.data!.docs.map((doc) {
                        final data =
                        doc.data() as Map<String, dynamic>;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.school,
                                  color: Color(0xFF1565C0)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data['name'] ??
                                          'Unnamed Course',
                                      style: const TextStyle(
                                          fontWeight:
                                          FontWeight.w600),
                                    ),
                                    Text(
                                      'Code: ${data['joinCode'] ?? ''}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color:
                                          Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy,
                                    size: 18,
                                    color: Color(0xFF1565C0)),
                                onPressed: () {
                                  final code =
                                      data['joinCode'] ?? '';
                                  if (code.isNotEmpty) {
                                    _copyCode(code);
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copyCode(String code) {
    // Copy to clipboard
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Join code "$code" copied!'),
        backgroundColor: const Color(0xFF2E7D32),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}