-- Course resources can contain any file type; authorization and size limits
-- continue to be enforced by the private bucket and storage policies.
update storage.buckets
set allowed_mime_types = null
where id = 'course-resources';

alter table public.resources
drop constraint if exists resources_file_size_bytes_check;

alter table public.resources
add constraint resources_file_size_bytes_check
check (file_size_bytes is null or file_size_bytes between 0 and 52428800);
