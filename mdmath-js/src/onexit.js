const callbacks = [];

function run() {
    callbacks.forEach(callback => callback());
}

process.on("exit", (code) => {
    run();
});

["SIGINT", "SIGTERM", "SIGHUP"].forEach((signal) => {
    process.on(signal, (_, code) => {
        process.exit(128 + code);
    });
});

export function addCallbackOnExit(callback) {
    callbacks.push(callback);
}
