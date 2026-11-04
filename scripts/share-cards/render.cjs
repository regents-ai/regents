// Draws the share pictures in platform/priv/static/images/share and checks where their words sit.
// Run from the repository root: node scripts/share-cards/render.cjs
const path = require("path");
const root = path.resolve(__dirname, "../..");
const { chromium } = require(path.join(root, "platform/node_modules/playwright"));

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
  let failed = false;
  for (const name of ["home", "stake", "redeem"]) {
    await page.goto(`file://${__dirname}/card.html?c=${name}`);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForFunction(() => [...document.images].every((image) => image.complete));
    const report = await page.evaluate(() => ({
      fonts: [...document.fonts].filter((font) => font.status === "loaded").map((font) => font.family),
      words: [".where", ".eyebrow", "h1", ".lede"].flatMap((selector) => {
        const element = document.querySelector(selector);
        if (!element) return [];
        const range = document.createRange();
        range.selectNodeContents(element);
        const { left, right, bottom } = range.getBoundingClientRect();
        return [{ selector, left, right, bottom }];
      }),
    }));
    const problems = [];
    if (!report.fonts.includes("Geist Serif")) problems.push("Geist Serif did not load");
    for (const { selector, left, right, bottom } of report.words) {
      if (right > 640) problems.push(`${selector} reaches x=${Math.round(right)}`);
      if (left <= 180 && bottom >= 554) problems.push(`${selector} sits under the site-name label`);
    }
    console.log(name, problems.length ? `PROBLEMS ${problems.join("; ")}` : "ok");
    failed ||= problems.length > 0;
    await page.screenshot({ path: path.join(root, `platform/priv/static/images/share/${name}.png`) });
  }

  const wide = await browser.newPage({ viewport: { width: 2048, height: 1024 }, deviceScaleFactor: 1 });
  await wide.goto(`file://${__dirname}/literature.html`);
  await wide.evaluate(() => document.fonts.ready);
  await wide.waitForFunction(() => [...document.images].every((image) => image.complete));
  await wide.screenshot({ path: path.join(root, "platform/priv/static/images/literature/share.png") });
  await browser.close();
  process.exit(failed ? 1 : 0);
})();
