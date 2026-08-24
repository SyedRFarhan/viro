// Shared helper: content hash of every source that compiles into the
// prebuilt bridge (libViroReact.a). The build script stamps it next to the
// lib; prepack refuses to publish when the stamp does not match the tree.
const { createHash } = require('crypto');
const { readFileSync, readdirSync, statSync } = require('fs');
const { join } = require('path');

function walk(dir, out) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (/\.(h|m|mm|swift)$/.test(name)) out.push(p);
  }
  return out;
}

function bridgeSourceHash(root) {
  const files = walk(join(root, 'ios/ViroReact'), []);
  for (const name of readdirSync(join(root, 'ios'))) {
    if (/\.(h|m|mm)$/.test(name)) files.push(join(root, 'ios', name));
  }
  files.sort();
  const h = createHash('sha256');
  for (const f of files) {
    h.update(f.slice(root.length));
    h.update(readFileSync(f));
  }
  return h.digest('hex');
}

module.exports = { bridgeSourceHash };
