// AcademicFlow — profileService
import { supabase } from '../supabaseClient.js';

// Only editable fields are exposed here. Academic identity fields
// are intentionally never included — attempting to send them will be
// rejected by the protect_academic_fields trigger anyway, but keeping
// them out of the client call is the honest version of that boundary.
export async function updateOwnProfile(userId, { full_name, phone, bio, avatar_url }) {
  const { data, error } = await supabase
    .from('profiles')
    .update({ full_name, phone, bio, avatar_url })
    .eq('id', userId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function uploadAvatar(userId, file) {
  const path = `${userId}/${Date.now()}_${file.name}`;
  const { error: uploadErr } = await supabase.storage.from('avatars').upload(path, file, { upsert: true });
  if (uploadErr) throw uploadErr;
  const { data } = supabase.storage.from('avatars').getPublicUrl(path);
  return data.publicUrl;
}

export async function requestAcademicChange({ studentId, fieldName, currentValue, requestedValue, reason }) {
  const { data, error } = await supabase
    .from('change_requests')
    .insert({
      student_id: studentId,
      field_name: fieldName,
      current_value: currentValue,
      requested_value: requestedValue,
      reason,
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function fetchMyChangeRequests(studentId) {
  const { data, error } = await supabase
    .from('change_requests')
    .select('*')
    .eq('student_id', studentId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data || [];
}
