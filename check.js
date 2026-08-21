const luaparse = require('luaparse');
const fs = require('fs');
let bad = 0;
for (const f of process.argv.slice(2)) {
  const src = fs.readFileSync(f, 'utf8');
  try {
    luaparse.parse(src, { luaVersion: '5.3', comments: false });
    console.log(`OK   ${f}  (${src.split('\n').length} lines)`);
  } catch (e) {
    bad++;
    const line = e.line || 0;
    const lines = src.split('\n');
    console.log(`FAIL ${f}: ${e.message}`);
    for (let i = Math.max(0, line - 4); i < Math.min(lines.length, line + 3); i++) {
      console.log(`  ${i + 1 === line ? '>>' : '  '} ${i + 1}: ${lines[i]}`);
    }
  }
}
process.exit(bad ? 1 : 0);
