const fs = require('fs');
const buf = fs.readFileSync('D:/data/test3_raw.json');
let raw = buf.toString('utf8');
if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);

console.log('Total length:', raw.length);
console.log('Char at 170:', raw.charCodeAt(170), JSON.stringify(raw[170]));
console.log('Char at 171:', raw.charCodeAt(171), JSON.stringify(raw[171]));
console.log('Char at 172:', raw.charCodeAt(172), JSON.stringify(raw[172]));
console.log('Char at 173:', raw.charCodeAt(173), JSON.stringify(raw[173]));
console.log('Char at 174:', raw.charCodeAt(174), JSON.stringify(raw[174]));
console.log('Context 160-200:');
for (let i = 160; i < 200; i++) {
  const c = raw[i];
  const code = raw.charCodeAt(i).toString(16);
  process.stdout.write(c === '"' ? 'QUOTE' : c === '\\' ? 'BSLASH' : c === '\r' ? 'CR' : c === '\n' ? 'LF' : c);
}
console.log('');
console.log('---bytes 160-200 hex---');
console.log(Buffer.from(raw.slice(160, 200), 'utf8').toString('hex'));
