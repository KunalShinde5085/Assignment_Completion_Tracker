// AcademicFlow — adminService
// Every call here is only meaningful if the caller actually holds the
// relevant permission — RLS enforces that server-side regardless of
// what the UI shows, so these functions don't re-check permissions
// client-side; they just surface the DB error if denied.
import { supabase } from '../supabaseClient.js';

export async function listUsers({ search = '', status = null } = {}) {
  let query = supabase.from('profiles').select('*').order('created_at', { ascending: false });
  if (search) query = query.ilike('full_name', `%${search}%`);
  if (status) query = query.eq('account_status', status);
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

export async function setAccountStatus(userId, status) {
  const { data, error } = await supabase
    .from('profiles')
    .update({ account_status: status })
    .eq('id', userId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function inviteAdmin({ email, institutionId, roleId }) {
  const { data, error } = await supabase
    .from('admin_invitations')
    .insert({ email, institution_id: institutionId, role_id: roleId })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function createSubject({ institutionId, programId, semesterId, name, code }) {
  const { data, error } = await supabase
    .from('subjects')
    .insert({ institution_id: institutionId, program_id: programId, semester_id: semesterId, name, code })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function createActivity({ subjectId, name, orderIndex = 0 }) {
  const { data, error } = await supabase
    .from('activities')
    .insert({ subject_id: subjectId, name, order_index: orderIndex })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function createSharedTask(task) {
  const { data, error } = await supabase.from('shared_tasks').insert(task).select().single();
  if (error) throw error;
  return data;
}

export async function addTaskScope(sharedTaskId, scopeType, scopeRefId) {
  const { data, error } = await supabase
    .from('task_scopes')
    .insert({ shared_task_id: sharedTaskId, scope_type: scopeType, scope_ref_id: scopeRefId })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function archiveSharedTask(id) {
  const { data, error } = await supabase
    .from('shared_tasks')
    .update({ lifecycle_status: 'archived' })
    .eq('id', id)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function listPendingProposals() {
  const { data, error } = await supabase
    .from('task_proposals')
    .select('*, profiles:proposed_by(full_name)')
    .eq('status', 'pending')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function reviewProposal(id, status, reviewNotes = '') {
  const { data: { user } } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from('task_proposals')
    .update({ status, review_notes: reviewNotes, reviewed_by: user?.id, reviewed_at: new Date().toISOString() })
    .eq('id', id)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function listOpenReports() {
  const { data, error } = await supabase
    .from('task_reports')
    .select('*, shared_tasks:shared_task_id(title)')
    .eq('status', 'open')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function resolveReport(id, status) {
  const { data: { user } } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from('task_reports')
    .update({ status, resolved_by: user?.id, resolved_at: new Date().toISOString() })
    .eq('id', id)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function listPendingChangeRequests() {
  const { data, error } = await supabase
    .from('change_requests')
    .select('*, profiles:student_id(full_name)')
    .eq('status', 'pending')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function reviewChangeRequest(id, status) {
  const { data: { user } } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from('change_requests')
    .update({ status, reviewed_by: user?.id })
    .eq('id', id)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function fetchInstitutionAnalytics() {
  // Aggregation kept simple for MVP: fetch effective status counts
  // client-side from a bounded set. For large institutions, replace
  // with a dedicated SQL view/materialized view.
  const { data, error } = await supabase
    .from('student_task_states')
    .select('status');
  if (error) throw error;
  const counts = { not_started: 0, in_progress: 0, ready_for_submission: 0, submitted: 0, verified: 0 };
  (data || []).forEach((row) => { counts[row.status] = (counts[row.status] || 0) + 1; });
  return counts;
}
