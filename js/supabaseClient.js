// AcademicFlow — Supabase client singleton.
// Relies on the Supabase JS CDN script being loaded first (see each
// HTML page's <script src="https://unpkg.com/@supabase/supabase-js@2">).
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

export const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});
