// AcademicFlow — date + urgency helpers shared across pages.

export function formatDeadline(iso) {
  if (!iso) return 'No deadline';
  const d = new Date(iso);
  const now = new Date();
  const diffMs = d - now;
  const diffDays = Math.round(diffMs / 86400000);

  const dateStr = d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
  if (diffDays < 0) return `Overdue · ${dateStr}`;
  if (diffDays === 0) return `Due today · ${dateStr}`;
  if (diffDays === 1) return `Due tomorrow · ${dateStr}`;
  if (diffDays <= 7) return `Due in ${diffDays} days · ${dateStr}`;
  return dateStr;
}

export function urgencyLevel(iso, status) {
  if (status === 'completed' || status === 'verified' || status === 'submitted') return 'done';
  if (!iso) return 'normal';
  const diffDays = Math.round((new Date(iso) - new Date()) / 86400000);
  if (diffDays < 0) return 'overdue';
  if (diffDays <= 2) return 'urgent';
  if (diffDays <= 7) return 'soon';
  return 'normal';
}

export function greeting() {
  const h = new Date().getHours();
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}
