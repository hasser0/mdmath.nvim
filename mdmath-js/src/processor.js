import { rmdirSync, unlinkSync, mkdirSync } from "fs";
import mathjax from "mathjax";
import { listen } from "./reader.js";
import { magick, rsvgConvert } from "./binaries.js";
import { randomBytes } from "node:crypto";
import { addCallbackOnExit } from "./onexit.js";

const DIRECTORY_SUFFIX = randomBytes(6).toString("hex");
const IMG_DIR = `/tmp/nvim-mdmath-${DIRECTORY_SUFFIX}`;
const equations = [];
let mathjaxProcessor = null;
// pixels
const zoomPixelsRatio = 16;
let displayZoom = 1;
let cellHeightInPixels = 0;
let cellWidthInPixels = 0;
// config
const methodsMap = {
  AdjustEquationToText: adjustEquationToText,
  AdjustTextToEquation: adjustTextToEquation,
};
let bottomLineRatio = 0;
let pixelPadding = 0;
let methods = { display: null, inline: null, };
let centerInline = true;
let centerDisplay = true;
let foreground = null;

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

async function equationToSVG(equation, opts) {
  try {
    const svg = await mathjaxProcessor.tex2svgPromise(equation, opts);
    return { svg: mathjaxProcessor.startup.adaptor.innerHTML(svg) }
  } catch (error) {
    if (error instanceof MathError) {
      return { error: error.message }
    }
    throw error;
  }
}

// isDisplay
// isCenter
// numberPixelsWidth
// numberPixelsHeight
// filename
// hash
// equation
// numberCellsWidth
// numberCellsHeight
// equationType
async function adjustEquationToText(svg, opts) {
  // zoom up to text width
  const currentDisplay = opts.isDisplay ? displayZoom : 1;
  let png = await rsvgConvert(svg, [
    "--zoom", `${currentDisplay * cellHeightInPixels / zoomPixelsRatio}`,
    "--width", `${opts.numberPixelsWidth}px`,
    "--height", `${opts.numberPixelsHeight}px`,
    "--format", "png",
  ]);

  const ceilPNGImage = Math.ceil(png.imageHeight / cellHeightInPixels) * cellHeightInPixels;
  const fullHeightText = cellHeightInPixels * opts.numberCellsHeight;
  const ceilImageHeight = opts.isDisplay ? fullHeightText : ceilPNGImage;
  const bottomLineHeight = bottomLineRatio * cellHeightInPixels;
  const args = ["png:-", "-trim", "+repage", "-background", "none"];
  if ((2 * bottomLineHeight + png.imageHeight) > ceilImageHeight || opts.isDisplay) {
    args.push(
      "-gravity", "center",
      "-extent", `${opts.numberPixelsWidth}x${ceilImageHeight}`,
    );
  } else {
    args.push(
      "-gravity", "south",
      "-splice", `0x${bottomLineHeight}`,
      "-extent", `${opts.numberPixelsWidth}x${ceilImageHeight}`,
    );
  }
  args.push(`png:${opts.filename}`);
  await magick(png.data, args);
  return new Promise((resolve, _) => {
    resolve({
      imageHeight: ceilImageHeight,
      imageWidth: opts.numberPixelsWidth,
    })
  });
}

async function adjustTextToEquation(svg, opts) {
  // zoom but keep under size limited to two cells in height
  const currentDisplay = opts.isDisplay ? displayZoom : 1;
  const argSVG = [
    "--zoom", `${currentDisplay * cellHeightInPixels / zoomPixelsRatio}`,
  ];
  if (!opts.isDisplay) {
    argSVG.push("--height", `${cellHeightInPixels}px`);
  }
  argSVG.push("--format", "png");
  let png = await rsvgConvert(svg, argSVG);



  const ceilPNGImage = Math.ceil(png.imageHeight / cellHeightInPixels) * cellHeightInPixels;
  const fullHeightText = cellHeightInPixels * opts.numberCellsHeight;
  const ceilImageHeight = opts.isDisplay ? fullHeightText : ceilPNGImage;
  const ceilImageWidth = Math.ceil(png.imageWidth / cellWidthInPixels) * cellWidthInPixels;
  const bottomLineHeight = bottomLineRatio * cellHeightInPixels;
  const args = ["png:-", "-trim", "+repage", "-background", "none"];
  if ((2 * bottomLineHeight + png.imageHeight) > ceilImageHeight || opts.isDisplay) {
    args.push(
      "-gravity", "center",
      "-extent", `${ceilImageWidth}x${ceilImageHeight}`,
    );
  } else {
    args.push(
      "-gravity", "south",
      "-splice", `0x${bottomLineHeight}`,
      "-extent", `${ceilImageWidth}x${ceilImageHeight}`,
    );
  }
  args.push(`png:${opts.filename}`);
  await magick(png.data, args);
  return new Promise((resolve, _) => {
    resolve({
      imageHeight: ceilImageHeight,
      imageWidth: ceilImageWidth,
    })
  });
}

async function processEquation(req) {
  req.isDisplay = (req.equationType === "display");
  const svg2png = methods[req.equationType];
  req.isCenter = (req.isDisplay && centerDisplay) || (!req.isDisplay && centerInline);
  req.numberPixelsWidth = req.numberCellsWidth * cellWidthInPixels;
  req.numberPixelsHeight = req.numberCellsHeight * cellHeightInPixels;
  req.filename = `${IMG_DIR}/${req.hash}.png`;

  if (!req.equation || req.equation.trim().length === 0) {
    send_json({
      type: "error",
      hash: req.hash,
      error: "Empty equation",
    });
    return
  }

  let result = await equationToSVG(req.equation, { display: req.isDisplay, });
  if (result.error) {
    send_json({
      type: "error",
      hash: req.hash,
      error: result.error,
    });
    return
  }
  let svg = result.svg.replace(/currentColor/g, foreground).replace(/style="[^"]+"/, "")
  equations.push(req.filename);
  let png = await svg2png(svg, req);

  send_json({
    type: "image",
    hash: req.hash,
    filename: req.filename,
    imageHeight: png.imageHeight,
    imageWidth: png.imageWidth,
  });
}

function processMessage(req) {
  if (req.type == "pixel") {
    cellWidthInPixels = req.cellWidthInPixels;
    cellHeightInPixels = req.cellHeightInPixels;
  } else if (req.type == "config") {
    bottomLineRatio = req.bottomLineRatio;
    pixelPadding = req.pixelPadding;
    displayZoom = req.displayZoom;
    methods["inline"] = methodsMap[req.inlineMethod];
    methods["display"] = methodsMap[req.displayMethod];
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
