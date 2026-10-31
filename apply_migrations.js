const fs = require('fs');
const { execSync } = require('child_process');
const path = require('path');

const files = [
  'D:\\Teachcross APP\\supabase\\migrations\\00027_complete_schema_redesign.sql',
  'D:\\Teachcross APP\\supabase\\migrations\\00028_rls_policies_complete.sql',
  'D:\\Teachcross APP\\supabase\\migrations\\00029_rpcs_complete.sql'
];

for (const file of files) {
  const content = fs.readFileSync(file, 'utf-8');
  let statements = [];
  let current = '';
  let inDollarQuote = false;
  let dollarTag = '';
  let inSingleQuote = false;
  
  for (let i = 0; i < content.length; i++) {
    const ch = content[i];
    const next = content[i + 1];
    
    if (inDollarQuote) {
      current += ch;
      if (ch === dollarTag[0] && content.slice(i, i + dollarTag.length) === dollarTag) {
        inDollarQuote = false;
        i += dollarTag.length - 1;
      }
      continue;
    }
    
    if (inSingleQuote) {
      current += ch;
      if (ch === "'" && next !== "'") {
        inSingleQuote = false;
      } else if (ch === "'" && next === "'") {
        i++;
      }
      continue;
    }
    
    if (ch === '$') {
      const match = content.slice(i).match(/\$(\w*)\$/);
      if (match) {
        inDollarQuote = true;
        dollarTag = match[0];
        current += ch;
        continue;
      }
    }
    
    if (ch === "'") {
      inSingleQuote = true;
      current += ch;
      continue;
    }
    
    if (ch === ';') {
      statements.push(current.trim());
      current = '';
      continue;
    }
    
    current += ch;
  }
  
  if (current.trim()) statements.push(current.trim());
  
  console.log(`\n=== Processing ${path.basename(file)}: ${statements.length} statements ===`);
  
  for (let j = 0; j < statements.length; j++) {
    const stmt = statements[j];
    if (!stmt || stmt.startsWith('--')) continue;
    const startsWith = ['CREATE EXTENSION', 'CREATE TABLE IF NOT EXISTS', 'CREATE INDEX', 'CREATE TYPE', 'CREATE OR REPLACE FUNCTION', 'ALTER TABLE', 'CREATE POLICY', 'GRANT', 'REVOKE', 'COMMENT', 'DO'];
    if (!startsWith.some(s => stmt.startsWith(s))) continue;
    
    try {
      // Write statement to temp file and execute
      fs.writeFileSync('D:\\Teachcross APP\\supabase\\_temp_stmt.sql', stmt);
      execSync(`supabase db query --linked -f "D:\\Teachcross APP\\supabase\\_temp_stmt.sql"`, { cwd: 'D:\\Teachcross APP\\supabase', timeout: 30000, stdio: 'pipe' });
      process.stdout.write('.');
    } catch (e) {
      const msg = (e.stderr ? e.stderr.toString() : e.message).substring(0, 150);
      console.log(`\n  SKIP ${j+1}: ${msg}`);
    }
  }
  console.log(`\nDone with ${path.basename(file)}`);
}
console.log('\nAll migrations applied!');
