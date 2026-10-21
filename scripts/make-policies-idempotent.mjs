// One-off maintenance script: make every CREATE POLICY in the given
// migrations idempotent by emitting a DROP POLICY IF EXISTS before it.
import { readFileSync, writeFileSync } from 'node:fs'

const files = process.argv.slice(2)
const re = /^CREATE POLICY\s+([A-Za-z0-9_]+)\s+ON\s+((?:public\.)?[A-Za-z0-9_]+)/gm

for (const file of files) {
  const src = readFileSync(file, 'utf8')
  let count = 0
  const out = src.replace(re, (_m, name, table) => {
    count++
    return `DROP POLICY IF EXISTS ${name} ON ${table};\nCREATE POLICY ${name} ON ${table}`
  })
  if (count > 0) {
    writeFileSync(file, out)
    console.log(`${file}: added ${count} DROP POLICY IF EXISTS guards`)
  } else {
    console.log(`${file}: no changes`)
  }
}
