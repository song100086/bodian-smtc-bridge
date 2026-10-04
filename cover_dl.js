// Cover-art downloader for the Bodian -> SMTC bridge.
// Usage: node cover_dl.js <url> <outPath>
// Downloads to <outPath>.part first, then renames, so the bridge never picks up a
// half-written file. Exists because this machine's .NET/schannel HTTPS stack is
// broken (SEC_E_NO_CREDENTIALS), so the bridge downloads with node instead and hands
// SMTC a local file.
const https = require('https');
const fs = require('fs');

const url = process.argv[2];
const out = process.argv[3];
const tmp = out + '.part';

function finish(err) {
  if (err) {
    try { fs.unlinkSync(tmp); } catch (e) { }
    console.log('ERR ' + err);
    return;
  }
  try {
    fs.renameSync(tmp, out);
    console.log('OK ' + fs.statSync(out).size);
  } catch (e) {
    console.log('ERR ' + e);
  }
}

if (!url || !out) { console.log('ERR usage: node cover_dl.js <url> <outPath>'); process.exit(1); }

const req = https.get(url, res => {
  if (res.statusCode !== 200) { res.resume(); finish('HTTP ' + res.statusCode); return; }
  const w = fs.createWriteStream(tmp);
  res.pipe(w);
  w.on('finish', () => { w.close(() => finish(null)); });
  w.on('error', finish);
});
req.on('error', finish);
req.setTimeout(15000, () => { req.destroy(); finish('timeout'); });
