const fs = require('fs');

const file = 'D:\\Teachcross APP\\supabase\\migrations\\00027_complete_schema_redesign.sql';
const lines = fs.readFileSync(file, 'utf-8').split('\n');

// Map of line numbers (1-based) to type names
const typeNames = {
  70: 'school_role',
  273: 'conversation_type',
  299: 'member_role',
  316: 'message_status',
  341: 'attachment_type',
  342: 'attachment_status',
  365: 'announcement_audience',
  366: 'announcement_category',
  392: 'moderation_verdict',
  432: 'job_status',
  486: 'mentor_approval_status',
  503: 'availability_status',
  517: 'doubt_status',
  572: 'booking_status',
  627: 'no_show_type',
  668: 'engagement_scale',
  692: 'allowance_action',
  729: 'slt_scope_type'
};

for (const [lineNum, typeName] of Object.entries(typeNames)) {
  const idx = parseInt(lineNum) - 1;
  if (lines[idx] && lines[idx].includes('CREATE TYPE  AS ENUM')) {
    lines[idx] = lines[idx].replace('CREATE TYPE  AS ENUM', `CREATE TYPE ${typeName} AS ENUM`);
  }
}

fs.writeFileSync(file, lines.join('\n'));
console.log('Done fixing type names');
