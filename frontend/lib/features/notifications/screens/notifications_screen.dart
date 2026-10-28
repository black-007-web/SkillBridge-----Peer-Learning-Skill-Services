import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/notification_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/notification_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (notifications.whenOrNull(
                data: (items) => items.any((item) => !item.isRead),
              ) ??
              false)
            IconButton(
              tooltip: 'Mark all as read',
              onPressed: () async {
                final service = ref.read(notificationServiceProvider);
                if (service == null) return;
                await service.markAllRead();
                ref.invalidate(notificationsProvider);
              },
              icon: const Icon(Icons.done_all),
            ),
        ],
      ),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Empty(
          icon: Icons.cloud_off_outlined,
          title: 'Notifications unavailable',
          message: 'Check your connection and try again.',
          action: TextButton(
            onPressed: () => ref.invalidate(notificationsProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (items) => items.isEmpty
            ? const _Empty(
                icon: Icons.notifications_none_rounded,
                title: 'You’re all caught up',
                message: 'Account and learning updates will appear here.',
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _NotificationCard(
                    item: items[index],
                    onTap: items[index].isRead
                        ? null
                        : () async {
                            final service = ref.read(
                              notificationServiceProvider,
                            );
                            if (service == null) return;
                            await service.markRead(items[index].id);
                            ref.invalidate(notificationsProvider);
                          },
                  ),
                ),
              ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});
  final AppNotification item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Icon(
          _icon(item.category),
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (!item.isRead)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          '${item.body}\n${_relative(item.createdAt)}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      isThreeLine: true,
    ),
  );

  IconData _icon(String category) => switch (category) {
    'course' => Icons.menu_book_outlined,
    'message' => Icons.chat_bubble_outline,
    'announcement' => Icons.campaign_outlined,
    'mentor' => Icons.school_outlined,
    _ => Icons.security_outlined,
  };
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    ),
  );
}

String _relative(DateTime value) {
  final delta = DateTime.now().difference(value.toLocal());
  if (delta.inMinutes < 1) return 'Just now';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  if (delta.inDays < 30) return '${delta.inDays}d ago';
  return '${value.month}/${value.day}/${value.year}';
}
