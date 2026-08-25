// AcademicFlow — call this first on every authenticated page.
// Redirects to login if there's no session, otherwise populates appState.
import { bootstrapSession, onAuthStateChange } from '../services/authService.js';

export async function requireSession() {
  const result = await bootstrapSession();
  if (!result || !result.user) {
    window.location.href = 'login.html';
    return null;
  }
  onAuthStateChange((session) => {
    if (!session) window.location.href = 'login.html';
  });
  return result;
}
