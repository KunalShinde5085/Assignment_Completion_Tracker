// AcademicFlow — admin.js
import { requireSession } from '../utils/guard.js';
import { renderSidebar } from '../components/sidebar.js';
import {
  fetchSubjectsForCurrentScope, fetchActivitiesForSubject, fetchDivisions, findDuplicates,
} from '../services/taskService.js';
import {
  createSharedTask, addTaskScope, listPendingProposals, reviewProposal,
  listOpenReports, resolveReport, listPendingChangeRequests, reviewChangeRequest,
  listUsers, setAccountStatus, fetchInstitutionAnalytics,
} from '../services/adminService.js';
import { appState } from '../state/appState.js';
import { el, qs, qsa, showToast } from '../utils/dom.js';

const session = await requireSession();
if (session) {
  renderSidebar('admin');
  wireTabs();
  await initTaskForm();
  await loadProposals();
  await loadReports();
  await loadChangeRequests();
  await loadUsers();
  await loadAnalytics();
}

function wireTabs() {
  qsa('#tab-row .tag-filter').forEach((btn) => {
    btn.addEventListener('click', () => {
      qsa('#tab-row .tag-filter').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      qsa('.tab-panel').forEach((p) => (p.style.display = 'none'));
      qs(`#tab-${btn.dataset.tab}`).style.display = 'block';
    });
  });
}

// ---------- New task ----------
let divisionsCache = [];

async function initTaskForm() {
  const [subjects, divisions] = await Promise.all([fetchSubjectsForCurrentScope(), fetchDivisions()]);
  divisionsCache = divisions;

  const subjectSel = qs('#t-subject');
  subjects.forEach((s) => subjectSel.appendChild(el('option', { value: s.id }, s.name)));
  await refreshActivities(subjectSel.value);
  subjectSel.addEventListener('change', () => refreshActivities(subjectSel.value));

  const scopeTypeSel = qs('#t-scope-type');
  const divisionPicker = el('select', { id: 't-division' });
  divisions.forEach((d) => divisionPicker.appendChild(el('option', { value: d.id }, d.name)));
  qs('#t-scope-type').insertAdjacentElement('afterend', divisionPicker);
  const toggleDivisionPicker = () => { divisionPicker.style.display = scopeTypeSel.value === 'division' ? 'block' : 'none'; };
  toggleDivisionPicker();
  scopeTypeSel.addEventListener('change', toggleDivisionPicker);

  qs('#check-dup-btn').addEventListener('click', async () => {
    const dupes = await findDuplicates({
      subjectId: subjectSel.value,
      activityId: qs('#t-activity').value,
      title: qs('#t-title').value.trim(),
      deadline: qs('#t-deadline').value ? new Date(qs('#t-deadline').value).toISOString() : null,
    });
    const warnEl = qs('#dup-warning');
    if (dupes.length) {
      warnEl.style.display = 'block';
      warnEl.textContent = `Possible duplicate: "${dupes[0].title}" already exists.`;
    } else {
      warnEl.style.display = 'block';
      warnEl.style.color = 'var(--success)';
      warnEl.textContent = 'No likely duplicates found.';
    }
  });

  qs('#task-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    try {
      const task = await createSharedTask({
        institution_id: appState.profile?.institution_id,
        subject_id: subjectSel.value || null,
        activity_id: qs('#t-activity').value || null,
        title: qs('#t-title').value.trim(),
        deadline: qs('#t-deadline').value ? new Date(qs('#t-deadline').value).toISOString() : null,
      });
      const scopeType = scopeTypeSel.value;
      await addTaskScope(task.id, scopeType, scopeType === 'division' ? divisionPicker.value : null);
      showToast('Task published.', 'success');
      qs('#task-form').reset();
    } catch (err) {
      showToast(err.message || 'Could not publish task.', 'error');
    }
  });
}

async function refreshActivities(subjectId) {
  const activitySel = qs('#t-activity');
  activitySel.innerHTML = '';
  if (!subjectId) return;
  const activities = await fetchActivitiesForSubject(subjectId);
  activities.forEach((a) => activitySel.appendChild(el('option', { value: a.id }, a.name)));
}

// ---------- Proposals ----------
async function loadProposals() {
  const container = qs('#proposals-list');
  try {
    const proposals = await listPendingProposals();
    container.innerHTML = '';
    if (!proposals.length) { container.appendChild(el('div', { class: 'empty-state' }, 'No pending proposals.')); return; }
    proposals.forEach((p) => {
      container.appendChild(
        el('div', { class: 'task-row' }, [
          el('div', {}, [
            el('div', { class: 'title' }, p.title),
            el('div', { class: 'meta' }, `Proposed by ${p.profiles?.full_name || 'a student'}`),
          ]),
          el('button', { class: 'secondary', onClick: () => act(p.id, 'approved') }, 'Approve'),
          el('button', { class: 'danger', onClick: () => act(p.id, 'rejected') }, 'Reject'),
        ])
      );
    });
  } catch (err) { showToast(err.message, 'error'); }

  async function act(id, status) {
    try { await reviewProposal(id, status); showToast(`Proposal ${status}.`, 'success'); await loadProposals(); }
    catch (err) { showToast(err.message, 'error'); }
  }
}

// ---------- Reports ----------
async function loadReports() {
  const container = qs('#reports-list');
  try {
    const reports = await listOpenReports();
    container.innerHTML = '';
    if (!reports.length) { container.appendChild(el('div', { class: 'empty-state' }, 'No open reports.')); return; }
    reports.forEach((r) => {
      container.appendChild(
        el('div', { class: 'task-row' }, [
          el('div', {}, [
            el('div', { class: 'title' }, `${r.reason} — ${r.shared_tasks?.title || ''}`),
            el('div', { class: 'meta' }, r.description || ''),
          ]),
          el('button', { class: 'secondary', onClick: () => act(r.id, 'resolved') }, 'Resolve'),
          el('button', { class: 'danger', onClick: () => act(r.id, 'dismissed') }, 'Dismiss'),
        ])
      );
    });
  } catch (err) { showToast(err.message, 'error'); }

  async function act(id, status) {
    try { await resolveReport(id, status); showToast('Report updated.', 'success'); await loadReports(); }
    catch (err) { showToast(err.message, 'error'); }
  }
}

// ---------- Change requests ----------
async function loadChangeRequests() {
  const container = qs('#changes-list');
  try {
    const reqs = await listPendingChangeRequests();
    container.innerHTML = '';
    if (!reqs.length) { container.appendChild(el('div', { class: 'empty-state' }, 'No pending change requests.')); return; }
    reqs.forEach((r) => {
      container.appendChild(
        el('div', { class: 'task-row' }, [
          el('div', {}, [
            el('div', { class: 'title' }, `${r.profiles?.full_name || 'Student'} — ${r.field_name}`),
            el('div', { class: 'meta' }, `${r.current_value || '—'} → ${r.requested_value}`),
          ]),
          el('button', { class: 'secondary', onClick: () => act(r.id, 'approved') }, 'Approve'),
          el('button', { class: 'danger', onClick: () => act(r.id, 'rejected') }, 'Reject'),
        ])
      );
    });
  } catch (err) { showToast(err.message, 'error'); }

  async function act(id, status) {
    try { await reviewChangeRequest(id, status); showToast('Change request updated.', 'success'); await loadChangeRequests(); }
    catch (err) { showToast(err.message, 'error'); }
  }
}

// ---------- Users ----------
async function loadUsers() {
  const container = qs('#users-list');
  try {
    const users = await listUsers();
    container.innerHTML = '';
    const table = el('table', {}, [
      el('thead', {}, el('tr', {}, [el('th', {}, 'Name'), el('th', {}, 'Status'), el('th', {}, 'Action')])),
    ]);
    const tbody = el('tbody');
    users.forEach((u) => {
      tbody.appendChild(
        el('tr', {}, [
          el('td', {}, u.full_name || '(no name)'),
          el('td', {}, u.account_status),
          el('td', {}, [
            el('button', {
              class: 'secondary',
              onClick: async () => {
                const next = u.account_status === 'active' ? 'suspended' : 'active';
                try { await setAccountStatus(u.id, next); showToast('Status updated.', 'success'); await loadUsers(); }
                catch (err) { showToast(err.message, 'error'); }
              },
            }, u.account_status === 'active' ? 'Suspend' : 'Activate'),
          ]),
        ])
      );
    });
    table.appendChild(tbody);
    container.appendChild(table);
  } catch (err) { showToast(err.message, 'error'); }
}

// ---------- Analytics ----------
async function loadAnalytics() {
  const container = qs('#analytics-panel');
  try {
    const counts = await fetchInstitutionAnalytics();
    container.innerHTML = '';
    Object.entries(counts).forEach(([status, n]) => {
      container.appendChild(el('div', { class: 'task-row' }, [
        el('div', { class: 'title' }, status.replace('_', ' ')),
        el('span', { class: 'status-tag' }, String(n)),
      ]));
    });
  } catch (err) { showToast(err.message, 'error'); }
}
