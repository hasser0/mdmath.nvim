import { makeAsyncStream } from "./async_stream.js";

const reader = {}

function response_fail(message) {
    console.error(`Error: ${message}`);
    process.exit(1);
}

reader.listen = function(callback) {
    const stream = makeAsyncStream(process.stdin, ":");

    async function loop() {
        while (await stream.waitReadable()) {
            const type = await stream.readString();
            if (type == "request") {
                const hashLength = await stream.readInt();
                const hash = await stream.readFixedString(hashLength);

                const inline = await stream.readInt();
                const flags = await stream.readInt();

                const color = (await stream.readString()).toLowerCase();
                if (!color.match(/^#[0-9a-f]{6}$/))
                    throw new Error(`Invalid color format: ${color}`);

                const width = await stream.readInt();

                const height = await stream.readInt();

                const length = await stream.readInt();
                const equation = await stream.readFixedString(length);

                const response = {
                    type,
                    hashLength,
                    hash,
                    width,
                    height,
                    inline,
                    flags,
                    color,
                    equation
                };
                callback(response);
            } else if(type == "setfloat") {
                const variable = await stream.readString();
                const value = await stream.readFloat();
                const response = {
                    type,
                    variable,
                    value,
                };
                callback(response);
            } else if(type == "setint") {
                const variable = await stream.readString();
                const value = await stream.readInt();
                const response = {
                    type,
                    variable,
                    value,
                };
                callback(response);
            } else {
                response_fail(`Invalid request type: ${type}`);
            }
        }
    }

    loop();
}

export default reader;
