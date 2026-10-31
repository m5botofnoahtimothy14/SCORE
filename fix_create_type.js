const fs = require('fs');

const file = 'D:\\Teachcross APP\\supabase\\migrations\\00027_complete_schema_redesign.sql';
let content = fs.readFileSync(file, 'utf-8');

// Process CREATE TYPE statements: wrap each in DO block
// Pattern: CREATE TYPE <name> AS ENUM ( ... );
// The enum body can span multiple lines
let result = '';
let i = 0;
while (i < content.length) {
  const idx = content.indexOf('CREATE TYPE ', i);
  if (idx === -1) {
    result += content.slice(i);
    break;
  }
  
  // Add everything before CREATE TYPE
  result += content.slice(i, idx);
  
  // Find the end of this CREATE TYPE statement (matching ); )
  const startIdx = idx;
  let depth = 0;
  let inString = false;
  let endIdx = -1;
  for (let j = idx; j < content.length; j++) {
    const ch = content[j];
    if (ch === "'") {
      inString = !inString;
    } else if (!inString) {
      if (ch === '(') depth++;
      else if (ch === ')') {
        depth--;
        if (depth === 0) {
          // Found closing paren, now find the semicolon
          for (let k = j + 1; k < content.length; k++) {
            if (content[k] === ';') {
              endIdx = k;
              break;
            }
            if (content[k] !== ' ' && content[k] !== '\n' && content[k] !== '\r') {
              break;
            }
          }
          break;
        }
      }
    }
  }
  
  if (endIdx === -1) {
    result += content.slice(idx);
    break;
  }
  
  const typeStmt = content.slice(idx, endIdx + 1);
  result += `DO $$ BEGIN ${typeStmt}; EXCEPTION WHEN duplicate_object THEN NULL; END $$;`;
  i = endIdx + 1;
}

fs.writeFileSync(file, result);
console.log('Done');
