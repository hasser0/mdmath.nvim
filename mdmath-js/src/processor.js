import { rmdirSync, unlinkSync, mkdirSync } from "fs";
import mathjax from "mathjax";
import { listen } from "./reader.js";
import { pngFitTo, rsvgConvert } from "./binaries.js";
import { randomBytes } from "node:crypto";
import { addCallbackOnExit } from "./onexit.js";
import { sendNotification } from "./debug.js";

const DIRECTORY_SUFFIX = randomBytes(6).toString("hex");
const IMG_DIR = `/tmp/nvim-mdmath-${DIRECTORY_SUFFIX}`;
const equations = [];
const svgCache = {};
let mathjaxProcessor = null;
// pixesl
const zoomPixelsRatio = 16
let cellHeightInPixels = 0
let cellWidthInPixels = 0
// config
let bottomLineRatio = 0
let pixelPadding = 0
let displayMethod = null
let inlineMethod = null
let centerInline = true
let centerDisplay = true
let foreground = null

class MathError extends Error {
  constructor(message) {
    super(message);
    this.name = "MathError";
  }
}

function send_json(resp) {
  const jsonStr = btoa(JSON.stringify(resp));
  process.stdout.write(`${jsonStr.length}:${jsonStr}:`);
}

// TODO make each convert method a class
async function equationToSVG(equation, opts) {
  if (equation in svgCache) {
    return svgCache[equation];
  }
  try {
    const svg = await mathjaxProcessor.tex2svgPromise(equation, opts);
    return svgCache[equation] = { svg: mathjaxProcessor.startup.adaptor.innerHTML(svg) }
  } catch (error) {
    if (error instanceof MathError) {
      return svgCache[equation] = { error: error.message }
    }
    throw error;
  }
}

async function processEquation(req) {
  const isDisplay = (req.equationType === "display");
  const config = {
    isDisplay: isDisplay,
    isCenter: (isDisplay && centerDisplay) || (!isDisplay && centerInline),
    terminalWidth: req.ncellsWidth * cellWidthInPixels,
    terminalHeight: req.ncellsHeight * cellHeightInPixels,
    filename: `${IMG_DIR}/${req.hash}.png`,
  }
  const method = isDisplay ? displayMethod : inlineMethod;

  if (!req.equation || req.equation.trim().length === 0) {
    send_json({
      type: "error",
      hash: req.hash,
      error: "Empty equation",
    });
    return
  }

  let result = await equationToSVG(req.equation, { display: config.isDisplay, });
  if (result.error) {
    send_json({
      type: "error",
      hash: hash,
      error: result.error,
    });
    return
  }

  let svg = result.svg.replace(/currentColor/g, foreground).replace(/style="[^"]+"/, "")
  let basePNG = await rsvgConvert(svg, { zoom: cellHeightInPixels / zoomPixelsRatio, });
  const pngFitOpts = {
    width: config.terminalWidth,
    height: config.terminalHeight,
    center: config.isCenter,
    method: method,
    bottomLineHeight: Math.floor(cellHeightInPixels * bottomLineRatio),
    pixelPadding: pixelPadding,
    imageHeight: basePNG.height,
    imageWidth: basePNG.width,
  }
  await pngFitTo(basePNG.data, config.filename, pngFitOpts);

  equations.push(config.filename);
  send_json({
    type: "image",
    hash: req.hash,
    filename: config.filename,
    imageHeight: pngFitOpts.height,
    imageWidth: pngFitOpts.width,
  });
}

function processMessage(req) {
  if (req.type == "pixel") {
    cellWidthInPixels = req.cellWidthInPixels;
    cellHeightInPixels = req.cellHeightInPixels;
  } else if (req.type == "config") {
    bottomLineRatio = req.bottomLineRatio;
    pixelPadding = req.pixelPadding;
    displayMethod = req.displayMethod;
    inlineMethod = req.inlineMethod;
    centerInline = req.centerInline;
    centerDisplay = req.centerDisplay;
    foreground = req.foreground;
  } else if (req.type == "image") {
    processEquation(req).catch((err) => {
      send_json({
        type: "error",
        hash: req.hash,
        error: err.message,
      });
    });
  }
}

function main() {
  mkdirSync(IMG_DIR, { recursive: true });

  addCallbackOnExit(() => {
    equations.forEach((filename) => {
      try {
        unlinkSync(filename);
      } catch (error) { }
    });

    try {
      rmdirSync(IMG_DIR);
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
    mathjaxProcessor = _mathjax;
    listen(processMessage);
  }).catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

main();
