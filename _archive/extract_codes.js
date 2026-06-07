const fs = require('fs');
const raw = fs.readFileSync('D:/data/test3_raw.json', 'utf8').replace(/^\uFEFF/, '');

// Extract all codes matching XXXXXX.SH or XXXXXX.SZ
const codeRegex = /"?(\d{6}\.[A-Z]{2})"?/g;
const codes = [...new Set([...raw.matchAll(codeRegex)].map(m => m[1]))];

console.log('Total unique codes found:', codes.length);
console.log('First 5 codes:', codes.slice(0, 5).join(', '));
console.log('Last 5 codes:', codes.slice(-5).join(', '));

const shCodes = codes.filter(c => c.endsWith('.SH'));
const szCodes = codes.filter(c => c.endsWith('.SZ'));
console.log('SH codes:', shCodes.length);
console.log('SZ codes:', szCodes.length);
console.log('All SH?:', szCodes.length === 0);

// Check prefixes (沪市主板 60/68开头 but 68是科创板, so for sh_main expect 60)
const shPrefixes = [...new Set(shCodes.map(c => c.split('.')[0].slice(0, 2)))].sort();
console.log('SH code prefixes:', shPrefixes.join(', '));

// Save clean code list
fs.writeFileSync('D:/data/lists/sh_main_codes.txt', codes.join('\n'), 'utf8');
console.log('Saved to D:/data/lists/sh_main_codes.txt');
