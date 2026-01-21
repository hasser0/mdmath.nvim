import { stat } from "node:fs";
import { spawn } from "node:child_process";

const PATH = process.env.PATH.split(":");

const fileExists = (filename) => new Promise((resolve, _) => {
  stat(filename, (err, stats) => {
    if (err) {
      return resolve(false);
    }
    resolve(stats.isFile());
  });
});

async function findBinary(name) {
  for (const path of PATH) {
    if (await fileExists(`${path}/${name}`)) {
      return `${path}/${name}`;
    }
  }
}

const rsvgBinary = new Promise(async (resolve) => {
  const rsvg = await findBinary("rsvg-convert");
  if (rsvg === null) {
    console.error("Failed to find rsvg-convert! Make sure to have it properly installed.");
    process.exit(1);
  }
  return resolve(rsvg);
})

const magickBinary = new Promise(async (resolve) => {
  // ImageMagick v7
  const magick = await findBinary("magick");
  if (magick !== null) {
    return resolve({
      convert: magick,
      identify: magick,
      isV7: true
    });
  }

  // ImageMagick v6
  const convert = await findBinary("convert");
  if (convert === null) {
    console.error("Failed to find ImageMagick v6/v7 (found neither convert nor magick)");
    process.exit(1);
  }
  const identify = await findBinary("identify");
  if (identify === null) {
    console.error("Failed to find ImageMagick v6/v7 (found convert, but not identify)");
    process.exit(1);
  }

  return resolve({
    convert,
    identify,
    isV7: false
  });
});

export async function pngFitTo(input, output, opts) {
  const size = `${opts.width}x${opts.height}`;
  const magick = await magickBinary;
  const { imageHeight, height, pixelPadding, bottomLineHeight } = opts;

  let args = ["png:-", "-trim", "+repage", "-background", "none"];

  // 1. If image is too tall: Shrink and add padding above/below
  if (imageHeight > height) {
    const shrinkTargetHeight = height - (pixelPadding * 2);
    args.push(
      "-resize", `x${shrinkTargetHeight}`,
      "-gravity", "center",
      "-extent", size
    );
  } else if (imageHeight < height && (2 * bottomLineHeight + imageHeight) > height) {
    // 2. If image is small but the "bottom line" would overflow: Just center it
    args.push(
      "-gravity", "center",
      "-extent", size
    );
  } else {
    // 3. If there is plenty of room: Trim bottom and add specific bottomLineHeight
    args.push(
      "-gravity", "south",
      "-splice", `0x${bottomLineHeight}`,
      "-extent", size
    );
  }
  args.push(`png:${output}`);

  return new Promise((resolve, reject) => {
    const p = spawn(magick.convert, args);
    let stderr = "";
    p.stderr.on("data", (chunk) => stderr += chunk);
    p.on("close", (code) => {
      if (code !== 0)
        return reject(new Error(`pngFitTo: ${stderr}`));

      resolve({ width: opts.width, height: opts.height });
    });
    p.stdin.write(input);
    p.stdin.end();
  });
}

export async function rsvgConvert(svg, opts) {
  const rsvg = await rsvgBinary;

  const args = [];
  args.push("--format", "png");
  for (const opt in opts) {
    args.push(`--${opt.replaceAll("_", "-")}`, opts[opt]);
  }

  return new Promise((resolve, reject) => {
    const p = spawn(rsvg, args);
    let chunks = [];
    p.stdout.on("data", (chunk) => chunks.push(chunk));
    p.on("close", (code) => {
      if (code !== 0)
        return reject(new Error(`rsvg-convert: exited with code ${code}`));

      const data = Buffer.concat(chunks);
      const pattern = "IHDR";
      const index = data.indexOf(pattern);
      if (index !== -1) {
        const widthIndex = index + 4;
        const heightIndex = widthIndex + 4;
        const width = data.readUInt32BE(widthIndex);
        const height = data.readUInt32BE(heightIndex);
        resolve({ data: data, width: width, height: height });
      }
    });
    p.stdin.write(svg);
    p.stdin.end();
  });
}

