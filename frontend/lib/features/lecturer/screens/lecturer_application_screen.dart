import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';

class LecturerApplicationScreen extends ConsumerStatefulWidget {
  const LecturerApplicationScreen({super.key});
  @override
  ConsumerState<LecturerApplicationScreen> createState() =>
      _LecturerApplicationScreenState();
}

class _LecturerApplicationScreenState
    extends ConsumerState<LecturerApplicationScreen> {
  final _form = GlobalKey<FormState>();
  final _department = TextEditingController();
  final _qualifications = TextEditingController();
  final _experience = TextEditingController();
  bool _loading = false;
  bool _loadingStatus = true;
  String? _status;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = ref.read(supabaseClientProvider);
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      setState(() {
        _loadingStatus = false;
        _loadError = 'Sign in to check your lecturer application status.';
      });
      return;
    }
    setState(() {
      _loadingStatus = true;
      _loadError = null;
    });
    try {
      final row = await client
          .from('lecturer_applications')
          .select('department,qualifications,experience,status')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() => _loadingStatus = false);
        return;
      }
      setState(() {
        _status = row['status'] as String?;
        _department.text = row['department'] as String? ?? '';
        _qualifications.text = row['qualifications'] as String? ?? '';
        _experience.text = row['experience'] as String? ?? '';
        _loadingStatus = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = '$error';
          _loadingStatus = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _department.dispose();
    _qualifications.dispose();
    _experience.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(supabaseClientProvider)!
          .rpc(
            'submit_lecturer_application',
            params: {
              'p_department': _department.text.trim(),
              'p_qualifications': _qualifications.text.trim(),
              'p_experience': _experience.text.trim(),
              'p_evidence_path': null,
            },
          );
      if (mounted) setState(() => _status = 'pending');
      ref.invalidate(currentRolesProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit application: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lecturer application')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_loadingStatus) const Center(child: CircularProgressIndicator()),
        if (_loadError != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: const Text('Could not load application status'),
              subtitle: SelectableText(_loadError!),
              trailing: IconButton(
                tooltip: 'Try again',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
        if (!_loadingStatus && _loadError == null) ...[
          if (_status != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text('Application status: $_status'),
                subtitle: const Text(
                  'You will receive an in-app notification when an administrator reviews your application.',
                ),
              ),
            ),
          if (_status != 'pending' && _status != 'approved')
            Form(
              key: _form,
              child: Column(
                children: [
                  TextFormField(
                    controller: _department,
                    decoration: const InputDecoration(labelText: 'Department'),
                    validator: (v) => (v?.trim().length ?? 0) < 2
                        ? 'Enter your department.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _qualifications,
                    decoration: const InputDecoration(
                      labelText: 'Qualifications',
                    ),
                    minLines: 3,
                    maxLines: 5,
                    validator: (v) => (v?.trim().length ?? 0) < 10
                        ? 'Add at least 10 characters.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _experience,
                    decoration: const InputDecoration(
                      labelText: 'Teaching or professional experience',
                    ),
                    minLines: 3,
                    maxLines: 5,
                    validator: (v) => (v?.trim().length ?? 0) < 10
                        ? 'Add at least 10 characters.'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: Text(
                      _loading ? 'Submitting...' : 'Submit application',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}
