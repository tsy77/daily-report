import { readFileSync, writeFileSync } from "fs";

const signals = JSON.parse(readFileSync("/Users/tsy/devspace/daily-report/output/signals.json", "utf-8"));
console.log("loaded", signals.length, "signals");
