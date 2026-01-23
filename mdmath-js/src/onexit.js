const callbacks = [];

process.on("exit", (_) => {
  callbacks.forEach(callback => callback());
});

["SIGINT", "SIGTERM", "SIGHUP"].forEach((signal) => {
  process.on(signal, (_, code) => {
    process.exit(128 + code);
  });
});

export function addCallbackOnExit(callback) {
  callbacks.push(callback);
}
