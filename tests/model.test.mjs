import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const dir = new URL("..", import.meta.url).pathname;
const source = fs
  .readFileSync(dir + "Model.js", "utf8")
  .replace(/^\.pragma library\s*$/m, "");

const context = { module: { exports: {} } };
vm.createContext(context);
vm.runInContext(source + "\nthis.Model = { parse, bytes, fileNames, short, deviceName, stateLabel, statusColor, percent };", context);
const Model = context.Model;

assert.equal(Model.parse('{"t":"ask","pin":"1234"}').pin, "1234");
assert.equal(Model.parse("not json"), null);
assert.equal(Model.bytes(0), "0 B");
assert.equal(Model.bytes(2048), "2.0 KB");
assert.equal(Model.fileNames(["a.txt", "b.txt"]), "a.txt, b.txt");
assert.equal(Model.short("abcdef", 4), "abc…");
assert.equal(Model.deviceName({ name: "Pixel 9" }), "Pixel 9");
assert.equal(Model.percent(5, 10), 0.5);
assert.equal(Model.statusColor("ready", null, "#fff"), "#4ADE80");
assert.equal(Model.statusColor("ready", {}, "#fff"), "#F87171");
assert.equal(Model.stateLabel("missing", "", (k) => k), "noBackend");

console.log("all model tests passed");
