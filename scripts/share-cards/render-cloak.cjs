// Renders Cloak's 1200x630 social share card (static PNG + animated GIF + MP4).
// Run from repo root: node scripts/share-cards/render-cloak.cjs
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const root = path.resolve(__dirname, "../..");
const { chromium } = require(path.join(root, "platform/node_modules/playwright"));
const ffmpeg = "/Users/sean/.darkbloom/bin/ffmpeg";
const iconGif = path.join(root, "platform/priv/static/images/cloak/icon-loop.gif");
const outPng = path.join(root, "platform/priv/static/images/share/cloak.png");
const outGif = path.join(root, "platform/priv/static/images/share/cloak.gif");
const outMp4 = "/Users/sean/.gemini/antigravity/brain/d6c111e9-fab1-4bd2-8094-703f23f0508b/cloak-share-card.mp4";

const tmpIcon = "/tmp/cloak-share-icon-frames";
const tmpCard = "/tmp/cloak-share-card-frames";
fs.rmSync(tmpIcon, { recursive: true, force: true });
fs.rmSync(tmpCard, { recursive: true, force: true });
fs.mkdirSync(tmpIcon, { recursive: true });
fs.mkdirSync(tmpCard, { recursive: true });

// Extract icon-loop.gif frames (160 frames @ 20fps = 8s)
execFileSync(ffmpeg, ["-y", "-i", iconGif, path.join(tmpIcon, "f_%03d.png")], { stdio: "ignore" });
const iconFiles = fs.readdirSync(tmpIcon).filter((f) => f.endsWith(".png")).sort();

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
  await page.goto(`file://${__dirname}/cloak.html`);
  await page.evaluate(() => document.fonts.ready);

  // Render 64 animation frames @ 16 fps (= 4.0s seamless loop).
  // Frame 0 is the peak hero frame (mid-dither crown + Step 1 done + Step 2 "Connecting to the Tor network." active @ 0:04)
  // so platforms that display only frame 0 of an animated GIF (like X/Twitter cards) show the strongest frame!
  const totalFrames = 64;
  const heroIconOffset = 17; // f_018: iconic mid-dither Cloak crown
  for (let i = 0; i < totalFrames; i++) {
    const iconIdx = (heroIconOffset + Math.floor((i / totalFrames) * iconFiles.length)) % iconFiles.length;
    const frameSrc = `file://${path.join(tmpIcon, iconFiles[iconIdx])}`;

    let activeIndex = 1;
    let timerText = "0:04";
    if (i < 20) {
      activeIndex = 1; // Connecting to the Tor network.
      timerText = "0:04";
    } else if (i < 40) {
      activeIndex = 2; // Loading local prompt rewriter model into memory.
      timerText = "0:05";
    } else if (i < 54) {
      activeIndex = 3; // Booting isolated Linux VM.
      timerText = "0:06";
    } else {
      activeIndex = 4; // Verifying Tor routing, prompt rewriting, and isolation.
      timerText = "0:07";
    }

    const spinPhase = (2 + i) % 8;
    await page.evaluate(
      (state) => window.renderState(state),
      { frameSrc, activeIndex, timerText, spinPhase }
    );
    await page.waitForFunction(() => {
      const img = document.getElementById("crown");
      return img && img.complete && img.naturalWidth > 0;
    });
    const framePath = path.join(tmpCard, `c_${String(i).padStart(3, "0")}.png`);
    await page.screenshot({ path: framePath });
    if (i === 0) {
      fs.copyFileSync(framePath, outPng);
    }
  }

  await browser.close();

  // Build smooth palette-optimized animated GIF (1200x630 @ 16fps)
  const palette = path.join(tmpCard, "palette.png");
  execFileSync(ffmpeg, [
    "-y", "-framerate", "16", "-i", path.join(tmpCard, "c_%03d.png"),
    "-vf", "palettegen=max_colors=96:stats_mode=diff",
    palette,
  ], { stdio: "ignore" });
  execFileSync(ffmpeg, [
    "-y", "-framerate", "16", "-i", path.join(tmpCard, "c_%03d.png"),
    "-i", palette,
    "-lavfi", "paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle",
    outGif,
  ], { stdio: "ignore" });

  // Build crisp H.264 MP4 (for X/Twitter direct video upload)
  execFileSync(ffmpeg, [
    "-y", "-framerate", "16", "-i", path.join(tmpCard, "c_%03d.png"),
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", "-movflags", "+faststart",
    outMp4,
  ], { stdio: "ignore" });

  console.log("PNG:", outPng, fs.statSync(outPng).size, "bytes");
  console.log("GIF:", outGif, fs.statSync(outGif).size, "bytes");
  console.log("MP4:", outMp4, fs.statSync(outMp4).size, "bytes");
})();
