-- ============================================================
-- AcademicFlow — 00_extensions.sql
-- Run this first.
-- ============================================================

create extension if not exists pgcrypto;   -- gen_random_uuid()
create extension if not exists citext;     -- case-insensitive email matching

-- Lock down the search_path for the whole session-safety story.
-- (Individual SECURITY DEFINER functions also set this explicitly —
--  belt and suspenders against search_path hijacking.)
