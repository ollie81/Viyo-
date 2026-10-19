-- "Steal My Setup" — extends the EXISTING `posts` table (not created
-- here; it's the main app's own table, written directly from Flutter
-- via RLS-scoped inserts — see PostService.createPost). Handed over
-- to run by hand in the Supabase SQL editor, same "no migration-runner
-- access from this codebase" constraint every other migration this
-- session has had.

-- The creator's own optional note on the gear/app/preset behind this
-- post (e.g. "iPhone 15, CapCut, Warm Film preset"). Null for every post
-- made before this column existed, or one where the creator just left
-- it blank — PostService.createPost already has a retry-without-
-- extra-fields fallback for exactly that transition window, so
-- nothing breaks before this is run.
alter table posts add column if not exists setup_note text;
