# Database design

The ordered migrations in `../supabase/migrations/` extend the existing auth
schema with Phase 1 workflows:

- `profiles` and `user_roles` hold profile, account status, and application
  roles separately. Users can read their own roles; only trusted admin RPCs or
  the first-admin SQL bootstrap can change them.
- `student_verification_requests` and `lecturer_applications` keep identity
  review separate from email verification. Admin decisions grant or update
  permissions in database triggers.
- `courses`, `course_modules`, `lessons`, `resource_folders`, and `resources`
  form the authoring model. Course owners can edit their own drafts and submit
  them; admins moderate publication. The `course-resources` bucket is private.
- `enrollments` records active, completed, and cancelled access. A partial
  unique index prevents multiple current enrollments for one user/course.
- `course_reviews` enforces one review per enrolled student/course and limits
  edits to the review's author. Moderation uses a restricted admin RPC.
- `announcements` and `announcement_deliveries` persist audience-targeted
  notices. Publishing runs in a transaction and creates one in-app notification
  per recipient.
- `support_tickets` restricts private reports to the reporter and admins;
  admin updates produce audit events in `audit_logs`.
- `notifications` are private to each recipient. Users may only mark their own
  rows as read. `transactional_email_outbox` remains server-only.

`SECURITY DEFINER` functions pin `search_path`, check the authenticated caller,
and expose only specific operations. Flutter route guards improve navigation,
but RLS and database triggers remain the authorization boundary. Apply all
migrations to a non-production Supabase project first and test them with users
from each role and account state before applying to production.
