import { test, expect, type Page } from "@playwright/test";

// Every id main.ts requires via el() — the boot contract.
const REQUIRED_IDS = [
  "url",
  "import",
  "addRow",
  "playpause",
  "prev",
  "next",
  "back",
  "fwd",
  "repeat",
  "scrubber",
  "elapsed",
  "remaining",
  "mute",
  "volume",
  "reverbType",
  "reverbCutoff",
  "speedKnob",
  "speed",
  "reverbKnob",
  "reverb",
  "queue",
  "gh",
  "now",
  "state",
  "status",
  "win-close",
  "win-min",
  "win-zoom",
  "console",
];

function trackErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  page.on("console", (m) => {
    if (m.type() === "error") errors.push(m.text());
  });
  return errors;
}

async function rackColumnCount(page: Page): Promise<number> {
  return page.evaluate(() => {
    const rack = document.querySelector(".rack")!;
    return getComputedStyle(rack).gridTemplateColumns.split(" ").length;
  });
}

async function hasHOverflow(page: Page): Promise<boolean> {
  return page.evaluate(() => {
    const el = document.scrollingElement!;
    return el.scrollWidth > el.clientWidth;
  });
}

test.describe("boot / contract", () => {
  test("loads with zero console errors and every required id present", async ({
    page,
  }) => {
    const errors = trackErrors(page);
    await page.goto("/");
    await expect(page.locator("#console")).toBeVisible();
    for (const id of REQUIRED_IDS) {
      await expect(page.locator(`#${id}`)).toBeAttached();
    }
    expect(errors).toEqual([]);
  });
});

test.describe("playback states (hash harness)", () => {
  test("idle: not playing", async ({ page }) => {
    await page.goto("/#state=idle");
    await expect(page.locator("#state")).toHaveText("idle");
    await expect(page.locator("html")).not.toHaveClass(/playing/);
  });

  test("downloading: surfaced as an independent indicator, state stays idle", async ({
    page,
  }) => {
    await page.goto("/#state=downloading");
    await expect(page.locator("#state")).toHaveText("idle");
    await expect(page.locator("#downloading")).toContainText("downloading");
    await expect(page.locator("#downloading")).toContainText("42%");
  });

  test("playing: console live, VU lit, reels spinning", async ({ page }) => {
    await page.goto("/#state=playing&queue=demo");
    await expect(page.locator("html")).toHaveClass(/playing/);
    await expect(page.locator("#playpause")).toHaveClass(/is-playing/);
    expect(await page.locator(".vu__track i.on").count()).toBeGreaterThan(0);
    // a running spin animation means a non-static transform on the reel
    const animated = await page.evaluate(() => {
      const reel = document.querySelector(".reel")!;
      return getComputedStyle(reel).animationName !== "none";
    });
    expect(animated).toBe(true);
  });

  test("paused: not playing", async ({ page }) => {
    await page.goto("/#state=paused");
    await expect(page.locator("#state")).toHaveText("paused");
    await expect(page.locator("html")).not.toHaveClass(/playing/);
  });

  test("failed: error styling + verbatim stderr", async ({ page }) => {
    await page.goto("/#state=failed");
    await expect(page.locator("#state")).toHaveText("failed");
    await expect(page.locator("#state")).toHaveClass(/error/);
    await expect(page.locator("#status")).toContainText("ERROR:");
  });
});

test.describe("views", () => {
  test("settings view activates via hash", async ({ page }) => {
    await page.goto("/#view=settings");
    await expect(page.locator('.view[data-view="settings"]')).toHaveClass(
      /is-active/,
    );
    await expect(page.locator('.view[data-view="player"]')).not.toHaveClass(
      /is-active/,
    );
  });

  test("library tab is disabled (soon)", async ({ page }) => {
    await page.goto("/");
    await expect(
      page.locator('.plate__nav .switch[data-view="library"]'),
    ).toBeDisabled();
  });
});

test.describe("adaptivity (tasks.md §8) — no horizontal overflow", () => {
  const cases = [
    { name: "wide", w: 1080, h: 720, cols: 3 },
    { name: "mid", w: 700, h: 700, cols: 2 },
    { name: "narrow", w: 360, h: 640, cols: 1 },
    { name: "min floor", w: 300, h: 460, cols: 1 },
  ];
  for (const c of cases) {
    test(`${c.name} (${c.w}×${c.h}): ${c.cols}-column rack, no overflow`, async ({
      page,
    }) => {
      await page.setViewportSize({ width: c.w, height: c.h });
      await page.goto("/#queue=demo");
      expect(await rackColumnCount(page)).toBe(c.cols);
      expect(await hasHOverflow(page)).toBe(false);
    });
  }

  test("narrow folds the up-next module away (cassette)", async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 480 });
    await page.goto("/#queue=demo");
    await expect(page.locator(".m-queue")).toBeHidden();
    await expect(page.locator(".m-tape .reel").first()).toBeVisible();
  });

  test("a very long track title never overflows", async ({ page }) => {
    await page.setViewportSize({ width: 720, height: 640 });
    await page.goto("/#queue=demo");
    const m = await page.evaluate(() => {
      document.getElementById("now")!.textContent =
        "An Absurdly Long Track Title That Goes On And On ".repeat(8);
      // the resize listener recomputes the marquee against the new text
      window.dispatchEvent(new Event("resize"));
      const deck = document.querySelector(".deck") as HTMLElement;
      const nowtitle = document.querySelector(".nowtitle") as HTMLElement;
      return {
        deckOverflows: deck.scrollWidth > deck.clientWidth,
        scrolling: nowtitle.classList.contains("is-scrolling"),
        shift: nowtitle.style.getPropertyValue("--marquee-shift"),
      };
    });
    // body scroller AND the deck itself stay within the window
    expect(await hasHOverflow(page)).toBe(false);
    expect(m.deckOverflows).toBe(false);
    // an overflowing title marquees, with a negative measured shift
    expect(m.scrolling).toBe(true);
    expect(parseFloat(m.shift)).toBeLessThan(0);
  });

  test("a long queue scrolls internally instead of squishing rows", async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1080, height: 720 });
    await page.goto("/#queue=demo");
    const m = await page.evaluate(() => {
      const ul = document.getElementById("queue")!;
      ul.replaceChildren(
        ...Array.from({ length: 90 }, (_, i) => {
          const li = document.createElement("li");
          li.textContent = `Track ${i + 1}`;
          return li;
        }),
      );
      // the list + add row size to content; .qwrap is the scroll container
      const wrap = document.querySelector(".qwrap")!;
      return {
        clientH: wrap.clientHeight,
        scrollH: wrap.scrollHeight,
        liH: (ul.firstElementChild as HTMLElement).clientHeight,
      };
    });
    // rows keep their natural height (not crushed) and the wrapper overflows
    expect(m.liH).toBeGreaterThan(20);
    expect(m.scrollH).toBeGreaterThan(m.clientH * 2);
  });
});

test.describe("knob interaction", () => {
  async function angle(page: Page, id: string): Promise<number> {
    return page.evaluate((knobId) => {
      const v = getComputedStyle(
        document.getElementById(knobId)!,
      ).getPropertyValue("--knob-angle");
      return parseFloat(v);
    }, id);
  }

  test("arrow keys move value, aria-valuenow, and the arc together", async ({
    page,
  }) => {
    await page.goto("/");
    const knob = page.locator("#speedKnob");
    await knob.focus();
    const before = Number(await page.locator("#speed").inputValue());
    const beforeAngle = await angle(page, "speedKnob");
    await knob.press("ArrowUp");
    const after = Number(await page.locator("#speed").inputValue());
    expect(after).toBe(before + 1);
    await expect(knob).toHaveAttribute("aria-valuenow", String(after));
    expect(await angle(page, "speedKnob")).toBeGreaterThan(beforeAngle);
  });

  test("wheel changes the value", async ({ page }) => {
    await page.goto("/");
    const knob = page.locator("#reverbKnob");
    const before = Number(await page.locator("#reverb").inputValue());
    await knob.hover();
    await page.mouse.wheel(0, -50); // up = increase
    expect(Number(await page.locator("#reverb").inputValue())).toBeGreaterThan(
      before,
    );
  });

  test("pointer drag changes the value", async ({ page }) => {
    await page.goto("/");
    const before = Number(await page.locator("#speed").inputValue());
    const box = (await page.locator("#speedKnob .knob__face").boundingBox())!;
    const cx = box.x + box.width / 2;
    const cy = box.y + box.height / 2;
    await page.mouse.move(cx + box.width / 4, cy);
    await page.mouse.down();
    await page.mouse.move(cx + box.width / 4 + 80, cy, { steps: 8 });
    await page.mouse.up();
    expect(Number(await page.locator("#speed").inputValue())).toBeGreaterThan(
      before,
    );
  });
});
