// AcademicFlow — minimal app-wide state. Kept intentionally small
// (section 85 of the plan): no framework, no localStorage of
// sensitive data, just an in-memory object plus a tiny pub/sub so
// pages can react when auth/profile state changes.

const listeners = new Set();

export const appState = {
  user: null,          // supabase auth user
  profile: null,       // row from `profiles`
  permissions: [],      // array of permission codes for the current user
};

export function setState(partial) {
  Object.assign(appState, partial);
  listeners.forEach((fn) => fn(appState));
}

export function subscribe(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function hasPermission(code) {
  return appState.permissions.includes(code);
}
