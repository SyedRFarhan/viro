// prepack gate: the published tarball ships ios/dist/lib/libViroReact.a.
// That lib silently went stale once (frozen at v2.61.50 while three
// releases shipped around it — Aug 23 2026). Never again: publishing is
// blocked unless the stamp written by `npm run build:bridge` matches the
// current bridge sources exactly.
const { readFileSync, existsSync } = require('fs');
const { join } = require('path');
const { bridgeSourceHash } = require('./bridge-hash');

const root = join(__dirname, '..');
const lib = join(root, 'ios/dist/lib/libViroReact.a');
const stamp = join(root, 'ios/dist/lib/.source-hash');

if (!existsSync(lib)) {
  console.error('prepack: ios/dist/lib/libViroReact.a is missing — run `npm run build:bridge`.');
  process.exit(1);
}
if (!existsSync(stamp)) {
  console.error('prepack: no freshness stamp for libViroReact.a — run `npm run build:bridge`.');
  process.exit(1);
}
const want = readFileSync(stamp, 'utf8').trim();
const have = bridgeSourceHash(root);
if (want !== have) {
  console.error('prepack: libViroReact.a is STALE — bridge sources changed since it was built.');
  console.error('         Run `npm run build:bridge` and re-publish.');
  process.exit(1);
}
console.log('prepack: prebuilt bridge is fresh (' + have.slice(0, 12) + ').');
