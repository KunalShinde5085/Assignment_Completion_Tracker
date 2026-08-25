// AcademicFlow — taskService
// All reads go through the my_tasks() RPC (see sql/02_functions.sql)
// so the "lazy state creation" default (not_started when no row
// exists yet) is computed server-side instead of duplicated in JS.
import { supabase } from '../supabaseClient.js';

export async function fetchMyTasks() {
  const { data, error } = await supabase.rpc('my_tasks');
  if (error) throw error;
  return data || [];
}

export async function fetchMyPersonalTasks() {
  const { data, error } = await supabase
    .from('personal_tasks')
    .select('*')
    .order('deadline', { ascending: true, nullsFirst: false });
  if (error) throw error;
  return data || [];
}

export async function createPersonalTask(task) {
  const { data, error } = await supabase.from('personal_tasks').insert(task).select().single();
  if (error) throw error;
  return data;
}

export async function updatePersonalTask(id, patch) {
  const { data, error } = await supabase.from('personal_tasks').update(patch).eq('id', id).select().single();
  if (error) throw error;
  return data;
}

export async function deletePersonalTask(id) {
  const { error } = await supabase.from('personal_tasks').delete().eq('id', id);
  if (error) throw error;
}

// Updates (or lazily creates) the caller's state row for a shared task.
// Relies on the unique(shared_task_id, student_id) constraint + RLS
// policies that only allow student_id = auth.uid().
export async function setSharedTaskStatus(sharedTaskId, studentId, status, extra = {}) {
  const payload = {
    shared_task_id: sharedTaskId,
    student_id: studentId,
    status,
    completed_at: status === 'verified' || status === 'submitted' ? new Date().toISOString() : null,
    ...extra,
  };
  const { data, error } = await supabase
    .from('student_task_states')
    .upsert(payload, { onConflict: 'shared_task_id,student_id' })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function fetchSubjectsForCurrentScope() {
  const { data, error } = await supabase.from('subjects').select('id, name, code').order('name');
  if (error) throw error;
  return data || [];
}

export async function fetchDivisions() {
  const { data, error } = await supabase.from('divisions').select('id, name').order('name');
  if (error) throw error;
  return data || [];
}

export async function fetchActivitiesForSubject(subjectId) {
  const { data, error } = await supabase
    .from('activities')
    .select('id, name, order_index')
    .eq('subject_id', subjectId)
    .order('order_index');
  if (error) throw error;
  return data || [];
}

export async function submitEvidence(sharedTaskId, studentId, file) {
  const path = `${studentId}/${sharedTaskId}/${Date.now()}_${file.name}`;
  const { error: uploadErr } = await supabase.storage.from('task-evidence').upload(path, file);
  if (uploadErr) throw uploadErr;

  const { data, error } = await supabase
    .from('task_submissions')
    .insert({
      shared_task_id: sharedTaskId,
      student_id: studentId,
      storage_path: path,
      file_name: file.name,
      mime_type: file.type,
      size_bytes: file.size,
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function createProposal(proposal) {
  const { data, error } = await supabase.from('task_proposals').insert(proposal).select().single();
  if (error) throw error;
  return data;
}

export async function findDuplicates({ subjectId, activityId, taskTypeId, title, deadline }) {
  const { data, error } = await supabase.rpc('find_possible_duplicates', {
    p_subject: subjectId || null,
    p_activity: activityId || null,
    p_task_type: taskTypeId || null,
    p_title: title,
    p_deadline: deadline || null,
  });
  if (error) throw error;
  return data || [];
}
