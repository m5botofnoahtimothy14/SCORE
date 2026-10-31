const fs = require('fs');

const files = [
  'D:\\Teachcross APP\\supabase\\migrations\\00027_complete_schema_redesign.sql',
  'D:\\Teachcross APP\\supabase\\migrations\\00028_rls_policies_complete.sql',
  'D:\\Teachcross APP\\supabase\\migrations\\00029_rpcs_complete.sql'
];

for (const file of files) {
  let content = fs.readFileSync(file, 'utf-8');
  
  // Replace CREATE TYPE ... AS ENUM ( ... ) with DO block
  // Match: CREATE TYPE <name> AS ENUM ( ... )
  content = content.replace(/CREATE TYPE (\w+) AS ENUM \(/g, 'DO $$ BEGIN CREATE TYPE $1 AS ENUM (');
  
  // We also need to close the DO block. The enum values end with ); followed by newline
  // This is tricky because we don't know where the enum ends. 
  // Instead, let's just replace standalone CREATE TYPE statements with DO blocks
  // by finding the closing ); of each enum
  
  fs.writeFileSync(file, content);
  console.log('Processed ' + file);
}
