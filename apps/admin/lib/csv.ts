import Papa from 'papaparse'

export interface StudentRow {
  first_name: string
  last_name: string
  student_id_no: string
  class_grade: string
  class_section: string
  date_of_birth?: string
  gender?: string
}

export interface TeacherRow {
  first_name: string
  last_name: string
  staff_id_no: string
  phone: string
  email?: string
  is_leadership?: boolean
  class_grade?: string
  class_section?: string
  subject?: string
}

export interface CsvResult<T> {
  rows: T[]
  errors: { line: number; message: string }[]
}

// Parses + validates a student roster CSV. Returns row-level errors and
// ONLY valid rows — callers must refuse to commit when errors exist, or
// commit valid rows explicitly after showing the error report.
export function parseStudentCsv(text: string): CsvResult<StudentRow> {
  const errors: CsvResult<StudentRow>['errors'] = []
  const rows: StudentRow[] = []
  const seen = new Set<string>()
  const parsed = Papa.parse<Record<string, string>>(text, { header: true, skipEmptyLines: true })
  parsed.data.forEach((r, i) => {
    const line = i + 2
    const row: StudentRow = {
      first_name: (r.first_name ?? '').trim(),
      last_name: (r.last_name ?? '').trim(),
      student_id_no: (r.student_id_no ?? '').trim(),
      class_grade: (r.class_grade ?? '').trim(),
      class_section: (r.class_section ?? '').trim(),
      date_of_birth: (r.date_of_birth ?? '').trim() || undefined,
      gender: (r.gender ?? '').trim() || undefined,
    }
    if (!row.first_name || !row.last_name) {
      errors.push({ line, message: 'first_name and last_name are required' })
      return
    }
    if (!row.student_id_no) {
      errors.push({ line, message: 'student_id_no is required' })
      return
    }
    if (seen.has(row.student_id_no)) {
      errors.push({ line, message: `duplicate student_id_no in file: ${row.student_id_no}` })
      return
    }
    seen.add(row.student_id_no)
    if (!row.class_grade) {
      errors.push({ line, message: 'class_grade is required' })
      return
    }
    rows.push(row)
  })
  return { rows, errors }
}

export function parseTeacherCsv(text: string): CsvResult<TeacherRow> {
  const errors: CsvResult<TeacherRow>['errors'] = []
  const rows: TeacherRow[] = []
  const seen = new Set<string>()
  const parsed = Papa.parse<Record<string, string>>(text, { header: true, skipEmptyLines: true })
  parsed.data.forEach((r, i) => {
    const line = i + 2
    const row: TeacherRow = {
      first_name: (r.first_name ?? '').trim(),
      last_name: (r.last_name ?? '').trim(),
      staff_id_no: (r.staff_id_no ?? '').trim(),
      phone: (r.phone ?? '').trim(),
      email: (r.email ?? '').trim() || undefined,
      is_leadership: ['true', '1', 'yes'].includes((r.is_leadership ?? '').trim().toLowerCase()),
      class_grade: (r.class_grade ?? '').trim() || undefined,
      class_section: (r.class_section ?? '').trim() || undefined,
      subject: (r.subject ?? '').trim() || undefined,
    }
    if (!row.first_name || !row.last_name) {
      errors.push({ line, message: 'first_name and last_name are required' })
      return
    }
    if (!row.staff_id_no) {
      errors.push({ line, message: 'staff_id_no is required' })
      return
    }
    if (seen.has(row.staff_id_no)) {
      errors.push({ line, message: `duplicate staff_id_no in file: ${row.staff_id_no}` })
      return
    }
    seen.add(row.staff_id_no)
    if (!/^\+[1-9]\d{6,14}$/.test(row.phone)) {
      errors.push({ line, message: `invalid phone (E.164 required): ${row.phone}` })
      return
    }
    rows.push(row)
  })
  return { rows, errors }
}

export const STUDENT_CSV_TEMPLATE =
  'first_name,last_name,student_id_no,class_grade,class_section,date_of_birth,gender\nAarav,Kumar,S1001,8,A,2014-05-01,M\n'

export const TEACHER_CSV_TEMPLATE =
  'first_name,last_name,staff_id_no,phone,email,is_leadership,class_grade,class_section,subject\nAsha,Sharma,T001,+911234567890,asha@school.edu.in,false,8,A,Mathematics\n'
