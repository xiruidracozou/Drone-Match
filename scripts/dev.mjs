import { spawn } from "node:child_process";
const children = [
  spawn("npm", ["run", "start", "-w", "@drone-match/api"], {
    stdio: "inherit",
    env: { ...process.env, DEMO_MODE: "true" },
  }),
  spawn("npm", ["run", "dev", "-w", "@drone-match/admin"], {
    stdio: "inherit",
  }),
];
let stopping = false;
function stop() {
  if (stopping) return;
  stopping = true;
  for (const child of children) child.kill("SIGTERM");
}
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
for (const child of children)
  child.on("exit", (code) => {
    if (!stopping) {
      process.exitCode = code || 1;
      stop();
    }
  });
