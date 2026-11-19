// The /design page in a real browser: accessibility (WCAG AA) in both themes, motion and
// reduced-motion behaviour, and no errors.
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

for (const colorScheme of ["light", "dark"] as const) {
  test.describe(`${colorScheme} theme`, () => {
    test.use({ colorScheme, reducedMotion: "reduce" });

    test("renders every component with no console errors", async ({ page }) => {
      const errors: string[] = [];
      page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
      page.on("pageerror", (e) => errors.push(String(e)));
      await page.goto("/design");
      for (const name of ["Button", "SeverityMarker", "SeverityGauge", "Nameplate", "PhotoFrame", "AppHeader", "BottomBar"]) {
        await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
      }
      expect(errors).toEqual([]);
    });

    test("passes axe WCAG 2.1 AA", async ({ page }) => {
      await page.goto("/design");
      const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
      expect(results.violations.map((v) => `${v.id}: ${v.nodes.length} (${v.help})`)).toEqual([]);
    });

    test("reduced motion shows final states", async ({ page }) => {
      await page.goto("/design");
      const needle = page.locator(".ds-needle").first();
      expect(await needle.evaluate((el) => getComputedStyle(el).animationName)).toBe("none");
      expect(await page.locator(".ds-marker-in").first().evaluate((el) => getComputedStyle(el).animationName)).toBe("none");
      expect(await page.locator(".ds-outline-draw").first().evaluate((el) => getComputedStyle(el).strokeDashoffset)).toMatch(/^0(px)?$/);
      await expect(page.locator(".ds-outline-pulse")).toBeHidden();
    });
  });
}

test.describe("motion", () => {
  test.use({ reducedMotion: "no-preference" });

  test("components animate with the token durations", async ({ page }) => {
    await page.goto("/design");
    const anim = (sel: string) =>
      page.locator(sel).first().evaluate((el) => {
        const s = getComputedStyle(el);
        return `${s.animationName} ${s.animationDuration}`;
      });
    expect(await anim(".ds-needle")).toBe("ds-needle 1.4s");
    expect(await anim(".ds-marker-in")).toBe("ds-marker-in 0.5s");
    expect(await anim(".ds-outline-draw")).toBe("ds-outline-draw 1.1s");
    expect(await anim(".ds-outline-pulse")).toBe("ds-outline-draw 2.4s");
  });

  test("the theme switch applies the dark tokens", async ({ page }) => {
    await page.goto("/design");
    await page.getByRole("button", { name: "Dark", exact: true }).click();
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
    expect(await page.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe("rgb(11, 16, 24)");
  });
});
