const fs = require('fs');
function stripBom(s) { if (s.charCodeAt(0) === 0xFEFF) s = s.slice(1); return s; }

const raw1 = stripBom(fs.readFileSync('D:/data/test1_raw.json', 'utf8'));
const d1 = JSON.parse(raw1);
const inner1 = JSON.parse(d1.content[0].text);
const rows1 = inner1.data.rows;
const cols1 = inner1.data.columns.map(c => c.name);

console.log('=== Test 1 (kline 600519.SH 2024) ===');
console.log('columns:', cols1.join(', '));
console.log('row count:', rows1.length);
console.log('rows with empty values:', rows1.filter(r => r.some(v => v === null || v === '')).length);
console.log('first row TIME:', rows1[0][0]);
console.log('first row _DATE:', rows1[0][cols1.indexOf('_DATE')]);
console.log('last row TIME:', rows1[rows1.length-1][0]);
console.log('last row _DATE:', rows1[rows1.length-1][cols1.indexOf('_DATE')]);
console.log('');

const raw3 = stripBom(fs.readFileSync('D:/data/test3_raw.json', 'utf8'));
const d3 = JSON.parse(raw3);
const inner3 = JSON.parse(d3.content[0].text);
const searchData = inner3.data.data[0];

console.log('=== Test 3 (search_stocks 沪市主板) ===');
console.log('excelTotalCount:', searchData.excelTotalCount);
console.log('rows count:', searchData.rows.length);
console.log('columns:', searchData.columns.map(c => c.name).join(', '));
console.log('first 3 codes:', searchData.rows.slice(0, 3).map(r => r[0]).join(', '));
console.log('last 3 codes:', searchData.rows.slice(-3).map(r => r[0]).join(', '));
const codes = searchData.rows.map(r => r[0]);
const codePrefixes = [...new Set(codes.map(c => c.split('.')[0]))];
console.log('unique exchange prefixes:', codePrefixes.join(', '));
console.log('all SH?:', codes.every(c => c.endsWith('.SH')));
