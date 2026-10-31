// ============================================================
// TeachCross — Shared Type Contracts
// ============================================================

// ── Database enums ──────────────────────────────────────────
export type SchoolRole = 'platform_owner' | 'school_admin' | 'principal' | 'head_teacher' | 'teacher' | 'student';
export type ConversationType = 'student_teacher' | 'student_support' | 'staff' | 'class_channel' | 'leadership';
export type MemberRole = 'student' | 'teacher' | 'admin_observer';
export type MessageStatus = 'pending_moderation' | 'approved' | 'blocked' | 'held_for_review' | 'deleted';
export type AttachmentType = 'image' | 'audio' | 'document' | 'video';
export type AttachmentStatus = 'uploading' | 'pending_scan' | 'approved' | 'quarantined' | 'rejected';
export type AnnouncementAudience = 'school_wide' | 'class' | 'staff' | 'leadership' | 'custom';
export type AnnouncementCategory = 'general' | 'academic' | 'event' | 'safety' | 'priority_alert';
export type ModerationVerdict = 'approved' | 'warned' | 'held' | 'blocked' | 'escalated';
export type ReviewStatus = 'pending' | 'under_review' | 'approved' | 'rejected' | 'escalated' | 'closed';
export type IncidentSeverity = 'low' | 'medium' | 'high' | 'critical';
export type IncidentStatus = 'open' | 'investigating' | 'escalated_external' | 'resolved' | 'closed';
export type QuestionStatus = 'open' | 'in_progress' | 'answered' | 'resolved';
export type InvestigationStatus = 'requested' | 'approved' | 'active' | 'expired' | 'revoked' | 'closed';
export type DoubtStatus = 'pending_assignment' | 'waiting' | 'assigned' | 'in_progress' | 'answered' | 'resolved' | 'reopened' | 'closed';
export type BookingStatus = 'requested' | 'confirmed' | 'cancelled_by_student' | 'cancelled_by_mentor' | 'completed' | 'no_show_student' | 'no_show_mentor' | 'unverified_closed';
export type NoShowType = 'student_no_show' | 'mentor_no_show';
export type EngagementScale = 'unprepared' | 'developing' | 'satisfactory' | 'strong' | 'outstanding';
export type AllowanceAction = 'deduct' | 'refund';
export type MentorApprovalStatus = 'pending' | 'approved' | 'rejected';
export type AvailabilityStatus = 'available' | 'away';
export type SltScopeType = 'program' | 'batch' | 'campus' | 'organisation';

// ── Core entities ───────────────────────────────────────────
export interface School {
  id: string;
  name: string;
  code: string;
  address?: string;
  city?: string;
  state?: string;
  country: string;
  phone?: string;
  email?: string;
  logo_url?: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface SchoolSettings {
  id: string;
  school_id: string;
  allow_student_id_only_login: boolean;
  require_activation_code: boolean;
  otp_provider: string;
  moderation_provider: string;
  image_safety_provider: string;
  max_file_size_mb: number;
  retention_days: number;
  timezone: string;
}

export interface UserProfile {
  id: string;
  display_name: string;
  phone?: string;
  avatar_url?: string;
  is_active: boolean;
  suspended_at?: string;
  suspension_reason?: string;
  created_at: string;
}

export interface SchoolMembership {
  id: string;
  user_id: string;
  school_id: string;
  role: SchoolRole;
  is_active: boolean;
  joined_at: string;
}

export interface AcademicYear {
  id: string;
  school_id: string;
  name: string;
  starts_on: string;
  ends_on: string;
  is_current: boolean;
}

export interface Class {
  id: string;
  school_id: string;
  academic_year_id: string;
  name: string;
  grade: string;
  section?: string;
  capacity?: number;
  is_active: boolean;
}

export interface Subject {
  id: string;
  school_id: string;
  name: string;
  code?: string;
}

export interface Student {
  id: string;
  school_id: string;
  user_id?: string;
  student_id_no: string;
  first_name: string;
  last_name: string;
  date_of_birth?: string;
  gender?: string;
  is_active: boolean;
  enrolled_on?: string;
}

export interface Teacher {
  id: string;
  school_id: string;
  user_id?: string;
  staff_id_no: string;
  first_name: string;
  last_name: string;
  phone: string;
  email?: string;
  is_active: boolean;
  is_leadership: boolean;
}

export interface Conversation {
  id: string;
  school_id: string;
  type: ConversationType;
  class_id?: string;
  title?: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  unread_count?: number;
}

export interface ConversationMember {
  id: string;
  conversation_id: string;
  user_id: string;
  role: MemberRole;
  can_send: boolean;
  joined_at: string;
  removed_at?: string;
  last_read_at?: string;
}

export interface Message {
  id: string;
  idempotency_key: string;
  conversation_id: string;
  school_id: string;
  sender_id: string;
  body?: string;
  status: MessageStatus;
  is_deleted: boolean;
  reply_to_id?: string;
  created_at: string;
  updated_at: string;
  // Joined fields
  sender?: UserProfile;
  attachments?: Attachment[];
}

export interface Attachment {
  id: string;
  message_id?: string;
  school_id: string;
  uploader_id: string;
  type: AttachmentType;
  file_name: string;
  mime_type: string;
  size_bytes: number;
  storage_path: string;
  status: AttachmentStatus;
  created_at: string;
}

export interface Announcement {
  id: string;
  school_id: string;
  author_id: string;
  title: string;
  body: string;
  category: AnnouncementCategory;
  audience_type: AnnouncementAudience;
  class_id?: string;
  requires_ack: boolean;
  is_published: boolean;
  published_at?: string;
  expires_at?: string;
  created_at: string;
}

export interface DoubtRequest {
  id: string;
  school_id: string;
  conversation_id: string;
  student_id: string;
  student_record_id: string;
  subject_id: string;
  question: string;
  chapter?: string;
  question_number?: string;
  explanation?: string;
  previous_attempts?: string;
  urgent: boolean;
  urgent_reason?: string;
  urgent_pass_used: boolean;
  status: DoubtStatus;
  assigned_mentor_id?: string;
  assigned_teacher_id?: string;
  named_mentor: boolean;
  first_reply_at?: string;
  resolved_at?: string;
  closed_at?: string;
  created_at: string;
  updated_at: string;
}

export interface SessionBooking {
  id: string;
  school_id: string;
  student_id: string;
  student_record_id: string;
  mentor_id: string;
  mentor_record_id: string;
  subject_id: string;
  duration_minutes: number;
  topic: string;
  preparation?: string;
  requested_at: string;
  scheduled_at?: string;
  confirmed_at?: string;
  meeting_link?: string;
  meeting_room?: string;
  status: BookingStatus;
  allowance_minutes_used: number;
  cancelled_at?: string;
  cancelled_by?: string;
  refunded: boolean;
  verification_code?: string;
  code_expires_at?: string;
  code_attempts: number;
  code_locked_at?: string;
  code_visible_at?: string;
  verified_at?: string;
  closed_without_code: boolean;
  close_reason?: string;
  google_meet_link?: string;
  google_calendar_event_id?: string;
  google_meet_created_at?: string;
  created_at: string;
  updated_at: string;
}

export interface Rating {
  id: string;
  school_id: string;
  request_id: string;
  student_id: string;
  mentor_id: string;
  rating: number;
  comment?: string;
  created_at: string;
}

export interface MentorAssessment {
  id: string;
  school_id: string;
  request_id: string;
  mentor_id: string;
  student_id: string;
  preparation: EngagementScale;
  engagement: EngagementScale;
  private_note?: string;
  created_at: string;
  updated_at: string;
}

export interface MentorDeskSettings {
  id: string;
  school_id: string;
  open_doubt_limit: number;
  session_allowance_minutes: number;
  urgent_passes_per_week: number;
  escalation_threshold_minutes: number;
  week_start_day: number;
  session_lengths: number[];
  verification_code_digits: number;
  code_visible_minutes_before: number;
  max_verification_attempts: number;
  created_at: string;
  updated_at: string;
}

export interface MentorSubjectApproval {
  id: string;
  school_id: string;
  teacher_id: string;
  subject_id: string;
  status: MentorApprovalStatus;
  approved_by?: string;
  approved_at?: string;
  created_at: string;
}

export interface MentorAvailability {
  id: string;
  school_id: string;
  teacher_id: string;
  status: AvailabilityStatus;
  updated_at: string;
}

export interface AllowanceTransaction {
  id: string;
  school_id: string;
  student_id: string;
  subject_id: string;
  booking_id?: string;
  week_start: string;
  action: AllowanceAction;
  minutes: number;
  reason?: string;
  created_at: string;
}

export interface UrgentPassUsage {
  id: string;
  school_id: string;
  student_id: string;
  subject_id: string;
  request_id: string;
  week_start: string;
  consumed_at: string;
}

export interface SltAccessGrant {
  id: string;
  school_id: string;
  user_id: string;
  granted_by: string;
  scope_type: SltScopeType;
  scope_value: string;
  created_at: string;
  revoked_at?: string;
}

export interface GoogleMeetConfig {
  id: string;
  school_id: string;
  calendar_id: string;
  time_zone: string;
  is_enabled: boolean;
  created_at: string;
  updated_at: string;
}

// ── Edge Function request/response types ────────────────────

export interface ActivateStudentRequest {
  school_id: string;
  student_id_no: string;
  activation_code: string;
}

export interface ActivateStudentResponse {
  success: boolean;
  student_id?: string;
  class_id?: string;
  error?: string;
}

export interface SendOtpRequest {
  phone: string;
  school_id: string;
  staff_id_no: string;
}

export interface VerifyOtpRequest {
  phone: string;
  otp: string;
  school_id: string;
  staff_id_no: string;
}

export interface SendMessageRequest {
  conversation_id: string;
  body: string;
  idempotency_key: string;
  reply_to_id?: string;
}

export interface SendMessageResponse {
  success: boolean;
  message_id?: string;
  duplicate?: boolean;
  error?: string;
}

export interface PublishAnnouncementRequest {
  school_id: string;
  title: string;
  body: string;
  category: AnnouncementCategory;
  audience_type: AnnouncementAudience;
  class_id?: string;
  requires_ack: boolean;
}

export interface ModerationResult {
  verdict: ModerationVerdict;
  categories: Record<string, number>;
  confidence?: number;
  provider: string;
}

export interface NotificationPayload {
  title: string;
  body: string;        // Generic — no sensitive content
  data: {
    type: string;      // 'message' | 'announcement' | 'alert'
    conversation_id?: string;
    announcement_id?: string;
    school_id: string;
  };
}

// ── API error envelope ───────────────────────────────────────
export interface ApiError {
  error: string;
  message: string;
  status: number;
}

