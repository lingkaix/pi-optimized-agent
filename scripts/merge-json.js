#!/usr/bin/env node
// merge-json.js — 幂等合并配置（只补缺失项，不覆盖用户已有值）
// 用法: node merge-json.js <target-file> <patch-file>
//  - packages        : 去重并集
//  - runTimeout      : target 已有则跳过，缺失才写入
//  - mcpServers      : 仅补 target 缺失的 server key
//  - 其余顶层 key    : target 已有则保留，缺失才补
import fs from 'node:fs';

const [, , targetFile, patchFile] = process.argv;
if (!targetFile || !patchFile) {
  console.error('usage: node merge-json.js <target-file> <patch-file>');
  process.exit(2);
}

const read = (f) => {
  try { return JSON.parse(fs.readFileSync(f, 'utf8')); }
  catch { return null; }
};

const target = read(targetFile) ?? {};
const patch = read(patchFile);
if (!patch) {
  console.error(`patch file not found or invalid: ${patchFile}`);
  process.exit(2);
}

let changed = false;
const mark = (k) => { changed = true; console.log(`  + ${k}`); };

for (const [key, pval] of Object.entries(patch)) {
  const tval = target[key];
  if (key === 'packages') {
    const merged = [...(Array.isArray(tval) ? tval : []), ...pval.filter((p) => !(tval || []).includes(p))];
    if (merged.length !== (tval || []).length) { target.packages = merged; mark('packages'); }
  } else if (key === 'mcpServers') {
    for (const [srv, scfg] of Object.entries(pval)) {
      if (!tval?.[srv]) { target.mcpServers = { ...(tval || {}), [srv]: scfg }; mark(`mcpServers.${srv}`); }
    }
  } else if (tval === undefined) {
    target[key] = pval;
    mark(key);
  }
}

if (changed) {
  fs.writeFileSync(targetFile, JSON.stringify(target, null, 2) + '\n');
} else {
  console.log('  (no changes needed)');
}
