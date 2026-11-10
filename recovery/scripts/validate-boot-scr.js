#!/usr/bin/env node
// Validate a Rockchip/vendor U-Boot script uImage (boot.scr).
//
//   node recovery/scripts/validate-boot-scr.js <boot.scr> [boot.cmd]
//
// Checks the uImage magic, header CRC32, payload CRC32, the Rockchip
// [length][0xFFFFFFFF] prefix, and (optionally) that the embedded script is
// exactly the non-empty, non-comment lines of boot.cmd.
const fs = require("fs");

function crc32(buf) {
  let c,
    crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c = (crc ^ buf[i]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xedb88320 : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function parse(path) {
  const b = fs.readFileSync(path);
  if (b.length < 72) throw new Error(`${path}: too short for a script uImage`);
  const magic = b.readUInt32BE(0);
  const hcrc = b.readUInt32BE(4);
  const ts = b.readUInt32BE(8);
  const size = b.readUInt32BE(12);
  const dcrc = b.readUInt32BE(24);
  const os = b[28];
  const arch = b[29];
  const type = b[30];
  const comp = b[31];
  const name = b.subarray(32, 64).toString("utf8").replace(/\0+$/, "");
  const payload = b.subarray(64);
  const headerZeroed = Buffer.from(b.subarray(0, 64));
  headerZeroed.writeUInt32BE(0, 4);
  const scriptLen = payload.readUInt32BE(0);
  const marker = payload.readUInt32BE(4);
  const script = payload.subarray(8);
  const problems = [];

  if (magic !== 0x27051956) problems.push(`bad magic 0x${magic.toString(16)}`);
  if (crc32(headerZeroed) !== hcrc) problems.push("header CRC mismatch");
  if (size !== payload.length) problems.push("uImage data-size mismatch");
  if (crc32(payload) !== dcrc) problems.push("payload CRC mismatch");
  if (marker !== 0xffffffff)
    problems.push(`bad Rockchip terminator 0x${marker.toString(16)}`);
  if (scriptLen !== script.length) problems.push("script length mismatch");
  if (type !== 6) problems.push(`unexpected image type ${type}`);

  console.log(`--- ${path}`);
  console.log(
    `filesize=${b.length} magic=0x${magic.toString(16)} hcrc=0x${hcrc.toString(16)}`,
  );
  console.log(
    `timestamp=${ts} (${new Date(ts * 1000).toISOString()}) size=${size} payload=${payload.length} dcrc=0x${dcrc.toString(16)}`,
  );
  console.log(
    `os=${os} arch=${arch} type=${type} comp=${comp} name=${JSON.stringify(name)}`,
  );
  console.log(
    `scriptLen=${scriptLen} marker=0x${marker.toString(16)} actualScriptLen=${script.length}`,
  );
  return { script, problems };
}

const [, , scrPath, cmdPath] = process.argv;
if (!scrPath) {
  console.error("usage: validate-boot-scr.js <boot.scr> [boot.cmd]");
  process.exit(2);
}

const { script, problems } = parse(scrPath);

if (cmdPath) {
  const stripped =
    fs
      .readFileSync(cmdPath, "utf8")
      .split("\n")
      .filter((line) => line.trim() && !line.trimStart().startsWith("#"))
      .join("\n") + "\n";
  const matches = script.equals(Buffer.from(stripped));
  console.log(`payload == stripped ${cmdPath}: ${matches ? "OK" : "MISMATCH"}`);
  if (!matches) problems.push("payload does not match boot.cmd");
}

if (problems.length) {
  console.error(`FAIL: ${problems.join("; ")}`);
  process.exit(1);
}
console.log("OK: script uImage is structurally valid");
