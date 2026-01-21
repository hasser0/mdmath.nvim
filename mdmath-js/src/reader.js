import { makeAsyncStream } from "./asyncStream.js";

export function listen(callback) {
  const stream = makeAsyncStream(process.stdin, ":");

  async function loop() {
    while (await stream.waitReadable()) {
      const jsonLength = await stream.readInt();
      const jsonValue = await stream.readFixedString(jsonLength);
      callback(JSON.parse(atob(jsonValue)));
    }
  }

  loop();
}
