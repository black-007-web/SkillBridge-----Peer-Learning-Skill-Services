import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';

class StudentVerificationScreen extends ConsumerStatefulWidget {
  const StudentVerificationScreen({super.key});
  @override
  ConsumerState<StudentVerificationScreen> createState() =>
      _StudentVerificationScreenState();
}

class _StudentVerificationScreenState
    extends ConsumerState<StudentVerificationScreen> {
  final _form = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _department = TextEditingController();
  final _program = TextEditingController();
  bool _loading = false;
  bool _loadingStatus = true;
  String? _status;
  String? _reason;
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
        _loadError = 'Sign in to check your student verification status.';
      });
      return;
    }
    setState(() {
      _loadingStatus = true;
      _loadError = null;
    });
    try {
      final profile = await client
          .from('profiles')
          .select('student_verification_status')
          .eq('id', user.id)
          .maybeSingle();
      final request = await client
          .from('student_verification_requests')
          .select('student_number,department,program,status,decision_reason')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        final profileStatus =
            profile?['student_verification_status'] as String?;
        _status =
            request?['status'] as String? ??
            (profileStatus == 'approved' ? profileStatus : null);
        if (request != null) {
          _number.text = request['student_number'] as String? ?? '';
          _department.text = request['department'] as String? ?? '';
          _program.text = request['program'] as String? ?? '';
          _reason = request['decision_reason'] as String?;
        }
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
    _number.dispose();
    _department.dispose();
    _program.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final client = ref.read(supabaseClientProvider)!;
      await client.rpc(
        'submit_student_verification',
        params: {
          'p_student_number': _number.text.trim(),
          'p_department': _department.text.trim(),
          'p_program': _program.text.trim(),
          'p_evidence_path': null,
        },
      );
      if (mounted) {
        setState(() {
          _status = 'pending';
          _reason = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification request submitted.')),
        );
      }
      ref.invalidate(currentProfileProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit verification: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = _status == 'approved';
    final pending = _status == 'pending';
    return Scaffold(
      appBar: AppBar(title: const Text('Student verification')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_loadingStatus) const Center(child: CircularProgressIndicator()),
          if (_loadError != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: const Text('Could not load verification status'),
                subtitle: SelectableText(_loadError!),
                trailing: IconButton(
                  tooltip: 'Try again',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          if (!_loadingStatus && _loadError == null) ...[
            Card(
              child: ListTile(
                leading: Icon(
                  approved
                      ? Icons.verified
                      : pending
                      ? Icons.hourglass_top
                      : Icons.info_outline,
                ),
                title: Text('Status: ${_status ?? 'Not submitted'}'),
                subtitle: Text(
                  approved
                      ? 'You can enroll in approved courses.'
                      : pending
                      ? 'An administrator will review your university details.'
                      : _reason ??
                            'Submit accurate university details for review.',
                ),
              ),
            ),
            if (!approved && !pending) ...[
              const SizedBox(height: 20),
              Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _number,
                      decoration: const InputDecoration(
                        labelText: 'Student number',
                      ),
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? 'Enter your student number.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _department,
                      decoration: const InputDecoration(
                        labelText: 'Department',
                      ),
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? 'Enter your department.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _program,
                      decoration: const InputDecoration(labelText: 'Program'),
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? 'Enter your program.'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: Text(
                        _loading ? 'Submitting...' : 'Submit for review',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
