const fs = require('fs');
function stripBom(s) { if (s.charCodeAt(0) === 0xFEFF) s = s.slice(1); return s; }

const buf = fs.readFileSync('D:/data/test3_raw.json');
console.log('First 10 bytes hex:', buf.slice(0, 10).toString('hex'));
let raw = buf.toString('utf8');
if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
console.log('After strip, first char code:', raw.charCodeAt(0));

try {
  const outer = JSON.parse(raw);
  console.log('Outer parse OK');
  const innerStr = outer.content[0].text;
  console.log('Inner string length:', innerStr.length);
  fs.writeFileSync('D:/data/test3_inner.json', innerStr, 'utf8');
  console.log('Inner JSON written to test3_inner.json');
  const inner = JSON.parse(innerStr);
  console.log('Inner parse OK');
  const searchData = inner.data.data[0];
  console.log('excelTotalCount:', searchData.excelTotalCount);
  console.log('rows count:', searchData.rows.length);
  console.log('columns:', searchData.columns.map(c => c.name).join(', '));
  const codes = searchData.rows.map(r => r[0]);
  console.log('First 3 codes:', codes.slice(0, 3).join(', '));
  console.log('Last 3 codes:', codes.slice(-3).join(', '));
  console.log('All SH?:', codes.every(c => c.endsWith('.SH')));
  console.log('Unique exchange prefixes:', [...new Set(codes.map(c => c.split('.')[1]))].join(', '));
} catch (e) {
  console.log('Error:', e.message);
  console.log('Position check - first 500 chars of raw:');
  console.log(raw.slice(0, 500));
}
