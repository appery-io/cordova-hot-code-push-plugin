/**
 * Verifies multi-update native-bridge preservation logic used by HCP.
 * Mirrors ContentManifest.isNativeBridgeFile + calculateDifference rules.
 *
 * Run: node scripts/test-native-bridge-diff.js
 */
'use strict';

function isNativeBridgeFile(fileName) {
  if (!fileName) return false;
  let name = String(fileName).replace(/\\/g, '/');
  if (name.startsWith('./')) name = name.slice(2);
  if (name === 'cordova.js' || name === 'cordova_plugins.js' ||
      name === 'cordova.js.map' || name === 'cordova_plugins.js.map') {
    return true;
  }
  if (name.startsWith('plugins/')) return true;
  return false;
}

function calculateDifference(oldFiles, newFiles) {
  const added = [];
  const changed = [];
  const deleted = [];

  for (const oldFile of oldFiles) {
    if (isNativeBridgeFile(oldFile.file)) continue;
    let found = false;
    for (const newFile of newFiles) {
      if (oldFile.file === newFile.file) {
        found = true;
        if (oldFile.hash !== newFile.hash && !isNativeBridgeFile(newFile.file)) {
          changed.push(newFile);
        }
        break;
      }
    }
    if (!found) deleted.push(oldFile);
  }

  for (const newFile of newFiles) {
    if (isNativeBridgeFile(newFile.file)) continue;
    if (!oldFiles.some(o => o.file === newFile.file)) {
      added.push(newFile);
    }
  }

  return { added, changed, deleted, updateFileList: added.concat(changed) };
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

// --- Fixtures mirroring Appery publishes ---
const bundled = [
  { file: 'index.html', hash: 'idx1' },
  { file: 'main.js', hash: 'main1' },
  { file: 'cordova.js', hash: 'native-cordova' },
  { file: 'cordova_plugins.js', hash: 'native-plugins-with-chcp' },
  { file: 'plugins/cordova-hot-code-push-plugin/www/chcp.js', hash: 'chcp-native' },
  { file: 'plugins/cordova-plugin-device/www/device.js', hash: 'device-native' },
];

const update1 = [
  { file: 'index.html', hash: 'idx2' }, // references cordova.aaa.js
  { file: 'main.js', hash: 'main2' },
  { file: 'cordova.aaa.js', hash: 'hash-aaa' },
  { file: 'cordova.js', hash: 'server-cordova' },
  { file: 'cordova_plugins.js', hash: 'server-plugins-NO-chcp' },
  { file: 'plugins/cordova-plugin-device/www/device.js', hash: 'device-server' },
  // server intentionally omits cordova-hot-code-push-plugin
];

const update2 = [
  { file: 'index.html', hash: 'idx3' },
  { file: 'main.js', hash: 'main3' },
  { file: 'cordova.bbb.js', hash: 'hash-bbb' },
  { file: 'cordova.js', hash: 'server-cordova-2' },
  { file: 'cordova_plugins.js', hash: 'server-plugins-NO-chcp-2' },
  { file: 'plugins/cordova-plugin-device/www/device.js', hash: 'device-server-2' },
];

// First update: bundled → update1
const d1 = calculateDifference(bundled, update1);
assert(d1.updateFileList.some(f => f.file === 'cordova.aaa.js'), 'update1 must download cordova.aaa.js');
assert(d1.updateFileList.some(f => f.file === 'index.html'), 'update1 must download index.html');
assert(d1.updateFileList.some(f => f.file === 'main.js'), 'update1 must download main.js');
assert(!d1.updateFileList.some(f => f.file === 'cordova.js'), 'must NOT replace cordova.js');
assert(!d1.updateFileList.some(f => f.file === 'cordova_plugins.js'), 'must NOT replace cordova_plugins.js');
assert(!d1.updateFileList.some(f => f.file.startsWith('plugins/')), 'must NOT replace plugins/*');
assert(!d1.deleted.some(f => f.file.startsWith('plugins/')), 'must NOT delete native plugins');
assert(!d1.deleted.some(f => f.file === 'cordova_plugins.js'), 'must NOT delete cordova_plugins.js');

// Simulate installed manifest persisted WITHOUT native bridge (as plugin now does)
const installed1 = update1.filter(f => !isNativeBridgeFile(f.file));
// Disk still has native bridge from copy-forward
const diskAfter1 = installed1.concat([
  { file: 'cordova.js', hash: 'native-cordova' },
  { file: 'cordova_plugins.js', hash: 'native-plugins-with-chcp' },
  { file: 'plugins/cordova-hot-code-push-plugin/www/chcp.js', hash: 'chcp-native' },
  { file: 'plugins/cordova-plugin-device/www/device.js', hash: 'device-native' },
]);

// Second update: already-updated app → update2
const d2 = calculateDifference(installed1, update2);
assert(d2.updateFileList.some(f => f.file === 'cordova.bbb.js'), 'update2 must download cordova.bbb.js');
assert(d2.deleted.some(f => f.file === 'cordova.aaa.js'), 'update2 must drop old cordova.aaa.js');
assert(!d2.updateFileList.some(f => isNativeBridgeFile(f.file)), 'update2 must not touch native bridge');
assert(diskAfter1.some(f => f.file === 'plugins/cordova-hot-code-push-plugin/www/chcp.js'),
  'chcp.js must still be on disk after update1');

// After update2 install: copy disk, apply deletes/adds
let disk = diskAfter1.slice();
for (const del of d2.deleted) {
  disk = disk.filter(f => f.file !== del.file);
}
for (const up of d2.updateFileList) {
  disk = disk.filter(f => f.file !== up.file).concat([up]);
}
assert(disk.some(f => f.file === 'cordova.bbb.js'), 'disk has new hashed cordova');
assert(!disk.some(f => f.file === 'cordova.aaa.js'), 'old hashed cordova removed');
assert(disk.some(f => f.file === 'cordova_plugins.js' && f.hash === 'native-plugins-with-chcp'),
  'native cordova_plugins.js preserved across second update');
assert(disk.some(f => f.file === 'plugins/cordova-hot-code-push-plugin/www/chcp.js'),
  'chcp plugin JS preserved across second update');
assert(disk.some(f => f.file === 'index.html' && f.hash === 'idx3'), 'content updated on second pass');

// Guard: hashed cordova must NOT be treated as native bridge
assert(!isNativeBridgeFile('cordova.37925731495c59ed.js'), 'hashed cordova must be downloadable');
assert(isNativeBridgeFile('cordova.js'), 'plain cordova.js protected');
assert(isNativeBridgeFile('plugins/foo/www/bar.js'), 'plugins/* protected');

console.log('OK: multi-update native-bridge preservation checks passed');
console.log('  update1 downloads:', d1.updateFileList.map(f => f.file).join(', '));
console.log('  update2 downloads:', d2.updateFileList.map(f => f.file).join(', '));
console.log('  update2 deletes:', d2.deleted.map(f => f.file).join(', '));
