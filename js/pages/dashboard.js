// AcademicFlow — dashboard.js
import { requireSession } from '../utils/guard.js';
import { renderSidebar } from '../components/sidebar.js';
import { fetchMyTasks } from '../services/taskService.js';
import { formatDeadline, urgencyLevel, greeting } from '../utils/date.js';
import { el, qs, showToast, setLoading } from '../utils/dom.js';
import { appState } from '../state/appState.js';

const session = await requireSession();
if (session) {
  renderSidebar('dashboard');
  qs('#greeting').textContent = `${greeting()}, ${appState.profile?.full_name?.split(' ')[0] || 'there'} 👋`;
  await loadDashboard();
}

async function loadDashboard() {
  const listEl = qs('#urgent-list');
  setLoading(true, listEl.closest('.card'));
  try {
    const tasks = await fetchMyTasks();
    renderStats(tasks);
    renderUrgent(tasks);
  } catch (err) {
    showToast(err.message || 'Could not load your tasks.', 'error');
  } finally {
    setLoading(false, listEl.closest('.card'));
  }
}

function renderStats(tasks) {
  const total = tasks.length;
  const completed = tasks.filter((t) => ['verified', 'submitted'].includes(t.effective_status)).length;
  const overdue = tasks.filter((t) => urgencyLevel(t.deadline, t.effective_status) === 'overdue').length;
  const remaining = total - completed;

  const cards = qs('#stat-grid').children;
  cards[0].querySelector('.value').textContent = total;
  cards[1].querySelector('.value').textContent = completed;
  cards[2].querySelector('.value').textContent = remaining;
  cards[3].querySelector('.value').textContent = overdue;
}

function renderUrgent(tasks) {
  const listEl = qs('#urgent-list');
  listEl.innerHTML = '';

  const urgent = tasks
    .filter((t) => !['verified', 'submitted'].includes(t.effective_status))
    .sort((a, b) => {
      const order = { overdue: 0, urgent: 1, soon: 2, normal: 3 };
      return order[urgencyLevel(a.deadline, a.effective_status)] - order[urgencyLevel(b.deadline, b.effective_status)];
    })
    .slice(0, 8);

  if (urgent.length === 0) {
    listEl.appendChild(el('div', { class: 'empty-state' }, 'Nothing urgent — you\'re caught up. 🎉'));
    return;
  }

  urgent.forEach((t) => {
    const level = urgencyLevel(t.deadline, t.effective_status);
    listEl.appendChild(
      el('div', { class: `task-row ${level}` }, [
        el('div', {}, [
          el('div', { class: 'title' }, t.title),
          el('div', { class: 'meta' }, formatDeadline(t.deadline)),
        ]),
        el('span', { class: `status-tag` }, t.effective_status.replace('_', ' ')),
      ])
    );
  });
}
