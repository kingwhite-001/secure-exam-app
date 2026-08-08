import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class JoinCourseScreen extends StatefulWidget {
  final String studentName;
  final String matricNumber;

  const JoinCourseScreen({
    super.key,
    required this.studentName,
    required this.matricNumber,
  });

  @override
  State<JoinCourseScreen> createState() => _JoinCourseScreenState();
}

class _JoinCourseScreenState extends State<JoinCourseScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitJoinRequest() async {
    final code = _codeController.text.trim().toUpperCase();

    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a join code')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No logged in user found');

      // Find the course matching this join code
      final courseQuery = await FirebaseFirestore.instance
          .collection('courses')
          .where('joinCode', isEqualTo: code)
          .limit(1)
          .get();

      if (courseQuery.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid join code. Please check and try again.')),
          );
        }
        return;
      }

      final courseDoc = courseQuery.docs.first;
      final courseId = courseDoc.id;
      final courseName = courseDoc.data()['name'] ?? 'Unnamed Course';
      final lecturerId = courseDoc.data()['lecturerId'];

      // Check if a request already exists for this student + course
      final existingRequest = await FirebaseFirestore.instance
          .collection('course_requests')
          .where('courseId', isEqualTo: courseId)
          .where('studentId', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (existingRequest.docs.isNotEmpty) {
        final status = existingRequest.docs.first.data()['status'];
        if (mounted) {
          String message;
          if (status == 'pending') {
            message = 'You already have a pending request for $courseName';
          } else if (status == 'approved') {
            message = 'You are already approved for $courseName';
          } else {
            message = 'Your previous request for $courseName was rejected. Contact your lecturer.';
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      }

      // Create the join request
      await FirebaseFirestore.instance.collection('course_requests').add({
        'courseId': courseId,
        'courseName': courseName,
        'lecturerId': lecturerId,
        'studentId': user.uid,
        'studentName': widget.studentName,
        'matricNumber': widget.matricNumber,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request sent for $courseName! Waiting for lecturer approval.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join a Course'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the Join Code given by your lecturer',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'e.g. CSC401-X7K2',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitJoinRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Text('Send Join Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}