import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// The 8 default avatar options: icon + background color pairs
const List<IconData> avatarIcons = [
  Icons.person,
  Icons.school,
  Icons.face,
  Icons.psychology,
  Icons.science,
  Icons.computer,
  Icons.menu_book,
  Icons.emoji_people,
];

const List<Color> avatarColors = [
  Color(0xFF1565C0), // blue
  Color(0xFF2E7D32), // green
  Color(0xFF6A1B9A), // purple
  Color(0xFFD84315), // deep orange
  Color(0xFF00838F), // teal
  Color(0xFFAD1457), // pink
  Color(0xFF4E342E), // brown
  Color(0xFF37474F), // blue grey
];

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController _institutionController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  int _selectedAvatar = 0;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          final data = doc.data();
          if (data != null) {
            _institutionController.text = data['institution'] ?? '';
            _departmentController.text = data['department'] ?? '';
            _bioController.text = data['bio'] ?? '';
            _selectedAvatar = data['avatarIndex'] ?? 0;
          }
        }
      }
    } catch (e) {
      // If loading fails, just start with blank fields
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No logged in user found');
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'institution': _institutionController.text.trim(),
        'department': _departmentController.text.trim(),
        'bio': _bioController.text.trim(),
        'avatarIndex': _selectedAvatar,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _institutionController.dispose();
    _departmentController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose an Avatar',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(avatarIcons.length, (index) {
                final isSelected = _selectedAvatar == index;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedAvatar = index;
                    });
                  },
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: avatarColors[index],
                    child: Stack(
                      children: [
                        Center(
                          child: Icon(
                            avatarIcons[index],
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_circle,
                                color: Color(0xFF2E7D32),
                                size: 18,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 28),
            const Text(
              'Institution',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _institutionController,
              decoration: InputDecoration(
                hintText: 'e.g. Nasarawa State University, Keffi',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Department / Field of Study',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _departmentController,
              decoration: InputDecoration(
                hintText: 'e.g. Computer Science',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Short Bio',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bioController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'e.g. Lecturer specializing in Software Engineering',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSaving
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Text('Save Profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}