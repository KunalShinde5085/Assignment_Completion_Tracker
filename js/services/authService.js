// AcademicFlow — authService
// Wraps Supabase Auth. Never stores or handles raw passwords outside
// of the calls below; Supabase Auth owns the credential store entirely.
import { supabase } from '../supabaseClient.js';
import { appState, setState } from '../state/appState.js';

export async function signUp({ email, password, fullName }) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { full_name: fullName } },
  });
  if (error) throw error;
  return data;
}

export async function signIn({ email, password }) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signOut() {
  await supabase.auth.signOut();
  setState({ user: null, profile: null, permissions: [] });
}

// Section 18: forgot password. Supabase emails a magic recovery link
// that lands on reset-password.html with a session already attached.
export async function sendPasswordReset(email) {
  const redirectTo = `${window.location.origin}/reset-password.html`;
  const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo });
  if (error) throw error;
}

// Section 19: change/reset password once the recovery session (or a
// normal logged-in session) is active.
export async function updatePassword(newPassword) {
  const { error } = await supabase.auth.updateUser({ password: newPassword });
  if (error) throw error;
}

export async function getCurrentUser() {
  const { data: { user } } = await supabase.auth.getUser();
  return user;
}

// Loads profile + flattened permission codes into appState. Call this
// once per page after confirming a session exists.
export async function bootstrapSession() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    setState({ user: null, profile: null, permissions: [] });
    return null;
  }

  const user = session.user;

  const [{ data: profile, error: profileErr }, { data: permRows, error: permErr }] = await Promise.all([
    supabase.from('profiles').select('*').eq('id', user.id).single(),
    supabase.rpc('current_user_permissions'),
  ]);

  if (profileErr) console.warn('Could not load profile:', profileErr.message);
  if (permErr) console.warn('Could not load permissions:', permErr.message);

  const permissions = (permRows || []).map((r) => (typeof r === 'string' ? r : r.current_user_permissions));

  setState({ user, profile: profile || null, permissions });
  return { user, profile, permissions };
}

export function onAuthStateChange(callback) {
  return supabase.auth.onAuthStateChange((_event, session) => callback(session));
}

export { appState };
