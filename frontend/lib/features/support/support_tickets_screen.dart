import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';

class SupportTicketsScreen extends ConsumerStatefulWidget {
  const SupportTicketsScreen({super.key});
  @override
  ConsumerState<SupportTicketsScreen> createState() =>
      _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends ConsumerState<SupportTicketsScreen> {
  late Future<List<Map<String, dynamic>>> _tickets;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final client = ref.read(supabaseClientProvider);
    final userId = client?.auth.currentUser?.id;
    _tickets = client == null || userId == null
        ? Future.error(StateError('Sign in to manage support tickets.'))
        : client
              .from('support_tickets')
              .select('id,category,subject,description,status,created_at')
              .eq('reporter_id', userId)
              .order('created_at', ascending: false)
              .then(
                (rows) =>
                    rows.map((row) => Map<String, dynamic>.from(row)).toList(),
              );
  }

  Future<void> _newTicket() async {
    final form = GlobalKey<FormState>();
    final subject = TextEditingController();
    final description = TextEditingController();
    var category = 'technical';
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Contact support'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items:
                        const [
                              'account',
                              'verification',
                              'course',
                              'resource',
                              'conduct',
                              'copyright',
                              'technical',
                              'suggestion',
                              'other',
                            ]
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                    onChanged: (v) => update(() => category = v ?? category),
                  ),
                  TextFormField(
                    controller: subject,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    validator: (v) => (v?.trim().length ?? 0) < 3
                        ? 'Enter at least 3 characters.'
                        : null,
                  ),
                  TextFormField(
                    controller: description,
                    decoration: const InputDecoration(
                      labelText: 'Describe the issue',
                    ),
                    minLines: 3,
                    maxLines: 6,
                    validator: (v) => (v?.trim().length ?? 0) < 10
                        ? 'Add at least 10 characters.'
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (submit == true) {
      try {
        final client = ref.read(supabaseClientProvider)!;
        final userId = client.auth.currentUser!.id;
        await client.from('support_tickets').insert({
          'reporter_id': userId,
          'category': category,
          'subject': subject.text.trim(),
          'description': description.text.trim(),
        });
        if (mounted) setState(_load);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not submit ticket: $error')),
          );
        }
      }
    }
    subject.dispose();
    description.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Help and support'),
      actions: [
        IconButton(
          onPressed: _newTicket,
          tooltip: 'New ticket',
          icon: const Icon(Icons.add_comment_outlined),
        ),
        IconButton(
          onPressed: () => setState(_load),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _tickets,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('${snapshot.error}'),
            ),
          );
        }
        final items = snapshot.requireData;
        if (items.isEmpty) {
          return const Center(
            child: Text('You have not submitted a support ticket.'),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => setState(_load),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: items
                .map(
                  (ticket) => Card(
                    child: ListTile(
                      title: Text('${ticket['subject']}'),
                      subtitle: Text(
                        '${ticket['category']} · ${ticket['status']}\n${ticket['description']}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: _newTicket,
      tooltip: 'New support ticket',
      child: const Icon(Icons.add),
    ),
  );
}
