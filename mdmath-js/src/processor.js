import fs from "fs";
import mathjax from "mathjax";
import reader from "./reader.js";
import { sendNotification }  from "./debug.js";
import { pngFitTo, rsvgConvert, pngDimensions } from "./magick.js";
import { randomBytes } from "node:crypto";
import { addCallbackOnExit } from "./onexit.js";

const DIRECTORY_SUFFIX = randomBytes(6).toString("hex");
const IMG_DIR = `/tmp/nvim-mdmath-${DIRECTORY_SUFFIX}`;
const equations = [];
const svgCache = {};
let Mathjax = undefined;
let cellHeightInPixels = null
let cellWidthInPixels = null
let bottomLineRatio = null
let pixelPadding = null
let zoomPixelsRatio = 16


class MathError extends Error {
    constructor(message) {
        super(message);
        this.name = "MathError";
    }
}

function mkdirSync(path) {
    try {
        fs.mkdirSync(path, { recursive: true });
    } catch (error) {
        throw error;
    }
}

function write(msg) {
    process.stdout.write(msg);
}

async function equationToSVG(equation, opts) {
    if (equation in svgCache) {
        return svgCache[equation];
    }

    try {
        const svg = await Mathjax.tex2svgPromise(equation, opts);
        return svgCache[equation] = { svg: Mathjax.startup.adaptor.innerHTML(svg) }
    } catch (error) {
        if (error instanceof MathError) {
            return svgCache[equation] = { error: error.message }
        }
        throw error;
    }
}

// hashLength, hash, cellWidth, cellHeight,
// width, height, flags, color, equation
async function processEquation(req) {
    const isCenter = !!(req.flags & 2);
    const isInline = !!(req.flags & 4);
    const terminalWidth = req.width * cellWidthInPixels;
    const terminalHeight = req.height * cellHeightInPixels;

    if (!req.equation || req.equation.trim().length === 0) {
        write(`error:${req.hash}:Empty equation:`)
        return
    }

    let result = await equationToSVG(req.equation, {
        display: !isInline,
    });
    if (result.error) {
        write(`error:${req.hash}:${result.error}:`)
       return
    }

    let svg = result.svg.replace(/currentColor/g, req.color).replace(/style="[^"]+"/, "")
    let basePNG = await rsvgConvert(svg, {
        zoom:  cellHeightInPixels / zoomPixelsRatio,
    });
    const filename = `${IMG_DIR}/${req.hash}.png`;
    equations.push(filename);

    await pngFitTo(basePNG.data, filename, {
        width: terminalWidth,
        height: terminalHeight,
        center: isCenter,
        bottomLineHeight: Math.floor(cellHeightInPixels * bottomLineRatio),
        pixelPadding: pixelPadding,
        imageHeight: basePNG.height,
        imageWidth: basePNG.width,
    });
    write(`image:${req.hash}:${filename}:`);
}

function processAll(req) {
    if (req.type === "request") {
        processEquation(req).catch((err) => {
            write(`error:${req.hash}:${err.message}:`)
        });
    } else if (req.type === "setfloat" && req.variable === "wpix") {
        cellWidthInPixels = req.value;
    } else if (req.type === "setfloat" && req.variable === "hpix") {
        cellHeightInPixels = req.value;
    } else if (req.type === "setfloat" && req.variable === "blratio") {
        bottomLineRatio = req.value;
    } else if (req.type === "setint" && req.variable === "ppad") {
        pixelPadding = req.value;
    }
}

function main() {
    mkdirSync(IMG_DIR);
    addCallbackOnExit(() => {
        equations.forEach((filename) => {
            try {
                fs.unlinkSync(filename);
            } catch (error) {
            }
        });

        try {
            fs.rmdirSync(IMG_DIR);
        } catch (error) { }
    });

    mathjax.init({
        loader: { load: ["input/tex", "output/svg"] },
        tex: {
            formatError: (_, error) => {
                throw new MathError(error.message);
            }
        }
    }).then((_mathjax) => {
        Mathjax = _mathjax;
        reader.listen(processAll);
    }).catch((error) => {
        console.error(error);
        process.exit(1);
    });
}

main();
