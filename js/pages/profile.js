// AcademicFlow — profile.js
import { requireSession } from '../utils/guard.js';
import { renderSidebar } from '../components/sidebar.js';
import { updateOwnProfile, requestAcademicChange } from '../services/profileService.js';
import { appState } from '../state/appState.js';
import { qs, showToast } from '../utils/dom.js';

const session = await requireSession();
if (session) {
  renderSidebar('profile');
  fillForm();
  wireForms();
}

function fillForm() {
  const p = appState.profile || {};
  qs('#full_name').value = p.full_name || '';
  qs('#phone').value = p.phone || '';
  qs('#bio').value = p.bio || '';

  qs('#academic-info').innerHTML = `
    Student ID: <strong>${p.student_id || '—'}</strong> ·
    Roll no: <strong>${p.roll_number || '—'}</strong><br/>
    Status: <strong>${p.account_status || '—'}</strong>
  `;
}

function wireForms() {
  qs('#profile-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    try {
      const updated = await updateOwnProfile(appState.user.id, {
        full_name: qs('#full_name').value.trim(),
        phone: qs('#phone').value.trim(),
        bio: qs('#bio').value.trim(),
        avatar_url: appState.profile?.avatar_url || null,
      });
      appState.profile = updated;
      showToast('Profile updated.', 'success');
    } catch (err) {
      showToast(err.message || 'Could not update profile.', 'error');
    }
  });

  qs('#request-change-btn').addEventListener('click', () => {
    qs('#change-request-form').style.display = 'block';
  });

  qs('#change-request-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    try {
      await requestAcademicChange({
        studentId: appState.user.id,
        fieldName: qs('#cr-field').value,
        currentValue: appState.profile?.[qs('#cr-field').value] || '',
        requestedValue: qs('#cr-value').value.trim(),
        reason: qs('#cr-reason').value.trim(),
      });
      showToast('Change request submitted for admin review.', 'success');
      qs('#change-request-form').reset();
      qs('#change-request-form').style.display = 'none';
    } catch (err) {
      showToast(err.message || 'Could not submit request.', 'error');
    }
  });
}
