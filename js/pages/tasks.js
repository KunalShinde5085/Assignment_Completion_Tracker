// AcademicFlow — tasks.js ("My Work" page)
import { requireSession } from '../utils/guard.js';
import { renderSidebar } from '../components/sidebar.js';
import {
  fetchMyTasks, fetchMyPersonalTasks, createPersonalTask,
  updatePersonalTask, setSharedTaskStatus,
} from '../services/taskService.js';
import { formatDeadline, urgencyLevel } from '../utils/date.js';
import { el, qs, qsa, showToast, setLoading } from '../utils/dom.js';
import { appState } from '../state/appState.js';

const session = await requireSession();
let sharedTasks = [];
let personalTasks = [];
let activeFilter = 'remaining';

if (session) {
  renderSidebar('tasks');
  wireFilterButtons();
  wirePersonalForm();
  await loadAll();
}

async function loadAll() {
  const listEl = qs('#task-list');
  setLoading(true, listEl.parentElement);
  try {
    [sharedTasks, personalTasks] = await Promise.all([fetchMyTasks(), fetchMyPersonalTasks()]);
    render();
  } catch (err) {
    showToast(err.message || 'Could not load tasks.', 'error');
  } finally {
    setLoading(false, listEl.parentElement);
  }
}

function wireFilterButtons() {
  qsa('.tag-filter').forEach((btn) => {
    btn.addEventListener('click', () => {
      qsa('.tag-filter').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      activeFilter = btn.dataset.filter;
      render();
    });
  });
}

function wirePersonalForm() {
  qs('#add-personal-btn').addEventListener('click', () => {
    qs('#add-personal-card').style.display = 'block';
  });
  qs('#cancel-personal').addEventListener('click', () => {
    qs('#add-personal-card').style.display = 'none';
  });
  qs('#personal-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const title = qs('#p-title').value.trim();
    const deadlineRaw = qs('#p-deadline').value;
    if (!title) return;
    try {
      await createPersonalTask({
        student_id: appState.user.id,
        title,
        deadline: deadlineRaw ? new Date(deadlineRaw).toISOString() : null,
      });
      qs('#personal-form').reset();
      qs('#add-personal-card').style.display = 'none';
      await loadAll();
      showToast('Personal task added.', 'success');
    } catch (err) {
      showToast(err.message || 'Could not add task.', 'error');
    }
  });
}

function combined() {
  const shared = sharedTasks.map((t) => ({
    kind: 'shared',
    id: t.task_id,
    title: t.title,
    deadline: t.deadline,
    status: t.effective_status,
  }));
  const personal = personalTasks.map((t) => ({
    kind: 'personal',
    id: t.id,
    title: t.title,
    deadline: t.deadline,
    status: t.status,
  }));
  return [...shared, ...personal];
}

function isDone(status) {
  return ['verified', 'submitted', 'completed'].includes(status);
}

function render() {
  const listEl = qs('#task-list');
  listEl.innerHTML = '';

  let items = combined();
  if (activeFilter === 'remaining') items = items.filter((t) => !isDone(t.status));
  else if (activeFilter === 'completed') items = items.filter((t) => isDone(t.status));
  else if (activeFilter === 'overdue') items = items.filter((t) => urgencyLevel(t.deadline, t.status) === 'overdue');
  else if (activeFilter === 'week') items = items.filter((t) => {
    const lvl = urgencyLevel(t.deadline, t.status);
    return lvl === 'urgent' || lvl === 'soon';
  });
  else if (activeFilter === 'personal') items = items.filter((t) => t.kind === 'personal');

  items.sort((a, b) => {
    const order = { overdue: 0, urgent: 1, soon: 2, normal: 3, done: 4 };
    return order[urgencyLevel(a.deadline, a.status)] - order[urgencyLevel(b.deadline, b.status)];
  });

  if (items.length === 0) {
    listEl.appendChild(el('div', { class: 'empty-state' }, 'Nothing here.'));
    return;
  }

  items.forEach((t) => {
    const level = urgencyLevel(t.deadline, t.status);
    const row = el('div', { class: `task-row ${level}` }, [
      el('div', {}, [
        el('div', { class: 'title' }, `${t.title}${t.kind === 'personal' ? ' (personal)' : ''}`),
        el('div', { class: 'meta' }, formatDeadline(t.deadline)),
      ]),
    ]);

    const select = el('select', {
      class: 'status-tag',
      style: 'margin-left:auto; width:auto;',
      onChange: async (e) => {
        try {
          if (t.kind === 'shared') {
            await setSharedTaskStatus(t.id, appState.user.id, e.target.value);
          } else {
            await updatePersonalTask(t.id, { status: e.target.value });
          }
          await loadAll();
        } catch (err) {
          showToast(err.message || 'Could not update status.', 'error');
        }
      },
    });

    const options = t.kind === 'shared'
      ? ['not_started', 'in_progress', 'ready_for_submission', 'submitted', 'verified']
      : ['not_started', 'in_progress', 'completed'];
    options.forEach((opt) => {
      const o = el('option', { value: opt }, opt.replace('_', ' '));
      if (opt === t.status) o.selected = true;
      select.appendChild(o);
    });

    row.appendChild(select);
    listEl.appendChild(row);
  });
}
