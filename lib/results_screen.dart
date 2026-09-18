import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('exam_results')
          .where('studentId', isEqualTo: user.uid)
          .get();

      final results = snapshot.docs.map((doc) {
        final data = doc.data();
        data['resultId'] = doc.id;
        return data;
      }).toList();

      // Sort by newest first
      results.sort((a, b) {
        final aTime = a['submittedAt'];
        final bTime = b['submittedAt'];
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown date';
    try {
      final dt = timestamp.toDate();
      return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown date';
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('My Results'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined,
                size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No results yet',
              style: TextStyle(
                  fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete an exam to see your results here',
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadResults,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _results.length,
          itemBuilder: (context, index) {
            final result = _results[index];
            final percentage =
                result['percentage'] as int? ?? 0;
            final score = result['score'] as int? ?? 0;
            final total = result['total'] as int? ?? 0;
            final passed = percentage >= 50;

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
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
                  // Top colored bar
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: passed
                          ? const Color(0xFF2E7D32)
                          : Colors.red,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                result['examTitle'] ??
                                    'Untitled Exam',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // Pass/Fail badge
                            Container(
                              padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4),
                              decoration: BoxDecoration(
                                color: passed
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFFFEBEE),
                                borderRadius:
                                BorderRadius.circular(20),
                              ),
                              child: Text(
                                passed ? 'PASSED' : 'FAILED',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: passed
                                      ? const Color(0xFF2E7D32)
                                      : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          result['courseName'] ?? '',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 14),

                        // Score row
                        Row(
                          children: [
                            // Score circle
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: passed
                                    ? const Color(0xFF2E7D32)
                                    : Colors.red,
                              ),
                              child: Center(
                                child: Text(
                                  '$percentage%',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  _infoRow(
                                    Icons.check_circle_outline,
                                    'Score',
                                    '$score / $total correct',
                                    Colors.green,
                                  ),
                                  const SizedBox(height: 6),
                                  _infoRow(
                                    Icons.timer_outlined,
                                    'Time taken',
                                    _formatTime(
                                        result['timeTakenSeconds']
                                        as int? ??
                                            0),
                                    Colors.orange,
                                  ),
                                  const SizedBox(height: 6),
                                  _infoRow(
                                    Icons.calendar_today_outlined,
                                    'Date',
                                    _formatDate(
                                        result['submittedAt']),
                                    Colors.blue,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (result['autoSubmitted'] == true) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius:
                              BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.orange.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline,
                                    size: 14,
                                    color: Colors.orange.shade700),
                                const SizedBox(width: 6),
                                Text(
                                  'Auto-submitted (time expired)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color:
                                      Colors.orange.shade700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _infoRow(
      IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}