import { exec } from "node:child_process";

export function sendNotification(message) {
  exec(`notify-send Processor.js: '${message}'`);
}
