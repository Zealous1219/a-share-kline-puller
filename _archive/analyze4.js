const fs = require('fs');
const buf = fs.readFileSync('D:/data/test3_inner.json');
console.log('Inner file size:', buf.length);
console.log('First 200 bytes hex:', buf.slice(0, 200).toString('hex'));
let raw = buf.toString('utf8');
console.log('Char at position 172:', raw.charCodeAt(172), JSON.stringify(raw[172]));
console.log('Context around 172 (165-185):');
for (let i = 165; i < 185; i++) {
  process.stdout.write(raw[i] + '(' + raw.charCodeAt(i).toString(16) + ')');
}
console.log('');
