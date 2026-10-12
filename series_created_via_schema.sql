-- VIYO series.created_via — extends the EXISTING `series` table (not
-- created here; it's the main app's own table, written directly from
-- Flutter via RLS-scoped inserts — see SeriesService.createSeries).
-- Handed over to run by hand in the Supabase SQL editor, same
-- "no migration-runner access from this codebase" constraint every
-- other migration this session has had.

-- Which Studio flow actually created this series: 'ai_drama_creator'
-- or 'paste_script'. Lets the Studio home screen's "Edit Cast" button
-- route to the right cast editor (new_drama_ai_screen.dart vs
-- viyo_studio_screen.dart) even for a brand-new, still-completely-
-- empty drama that has no plot or cast yet for any other check to key
-- off of. Null for every series created before this column existed —
-- SeriesService.createSeries already has a retry-without-extra-fields
-- fallback for exactly that transition window, so nothing breaks
-- before this is run.
alter table series add column if not exists created_via text;
