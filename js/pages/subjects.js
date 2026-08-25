// AcademicFlow — subjects.js
import { requireSession } from '../utils/guard.js';
import { renderSidebar } from '../components/sidebar.js';
import { fetchMyTasks, fetchSubjectsForCurrentScope } from '../services/taskService.js';
import { el, qs, showToast } from '../utils/dom.js';

const session = await requireSession();
if (session) {
  renderSidebar('subjects');
  await load();
}

async function load() {
  const grid = qs('#subject-grid');
  try {
    const [subjects, tasks] = await Promise.all([fetchSubjectsForCurrentScope(), fetchMyTasks()]);
    grid.innerHTML = '';

    if (subjects.length === 0) {
      grid.replaceWith(el('div', { class: 'empty-state' }, 'No subjects have been set up yet.'));
      return;
    }

    subjects.forEach((s) => {
      const subjectTasks = tasks.filter((t) => t.subject_id === s.id);
      const total = subjectTasks.length;
      const done = subjectTasks.filter((t) => ['verified', 'submitted'].includes(t.effective_status)).length;
      const pct = total ? Math.round((done / total) * 100) : 0;

      grid.appendChild(
        el('div', { class: 'card' }, [
          el('div', { style: 'display:flex; justify-content:space-between; align-items:baseline;' }, [
            el('h3', { style: 'margin:0;' }, s.name),
            el('span', { class: 'meta', style: 'color:var(--text-muted); font-size:.85rem;' }, `${pct}%`),
          ]),
          el('div', { class: 'progress-bar', style: 'margin:10px 0;' }, [
            el('div', { style: `width:${pct}%;` }),
          ]),
          el('div', { class: 'meta' }, total ? `${done} of ${total} tasks completed` : 'No tasks yet'),
        ])
      );
    });
  } catch (err) {
    showToast(err.message || 'Could not load subjects.', 'error');
  }
}
