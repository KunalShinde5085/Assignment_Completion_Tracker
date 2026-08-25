// AcademicFlow — sidebar component. Renders nav + hides Admin link
// unless the current user holds a management permission.
import { el, qs } from '../utils/dom.js';
import { appState } from '../state/appState.js';
import { signOut } from '../services/authService.js';

export function renderSidebar(activePage) {
  const mount = qs('#sidebar');
  if (!mount) return;

  const links = [
    { href: 'dashboard.html', label: '🏠 Dashboard', key: 'dashboard' },
    { href: 'tasks.html', label: '✅ My Work', key: 'tasks' },
    { href: 'subjects.html', label: '📚 Subjects', key: 'subjects' },
    { href: 'profile.html', label: '👤 Profile', key: 'profile' },
  ];

  const isStaff = appState.permissions.some((p) =>
    ['manage_users', 'manage_subjects', 'create_tasks', 'edit_tasks', 'approve_tasks', 'verify_tasks'].includes(p)
  );
  if (isStaff) links.push({ href: 'admin.html', label: '🛠 Admin', key: 'admin' });

  mount.innerHTML = '';
  mount.appendChild(el('div', { class: 'brand' }, 'AcademicFlow'));
  links.forEach((l) => {
    mount.appendChild(el('a', { href: l.href, class: l.key === activePage ? 'active' : '' }, l.label));
  });
  mount.appendChild(el('div', { class: 'spacer' }));
  mount.appendChild(
    el('a', {
      href: '#',
      onClick: async (e) => {
        e.preventDefault();
        await signOut();
        window.location.href = 'login.html';
      },
    }, '🚪 Sign out')
  );
}
