// Utitiy functions for debugging
import { exec } from 'node:child_process';
import fs from 'fs';

export async function saveFile(filename, data) {
    return new Promise((resolve, reject) => {
        fs.writeFile(filename, data, (err) => {
            if (err) {
                reject(err);
            } else {
                resolve();
            }
        });
    });
}

export function sendNotification(message) {
    exec(`notify-send Processor.js: '${message}'`);
}
