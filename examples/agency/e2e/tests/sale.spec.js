import { test, expect } from "@playwright/test";

function anAddress(street) {
  return `${Math.floor(Math.random() * 900) + 1} ${street}`;
}

async function connected(page) {
  await page.waitForFunction(() => window.liveSocket && window.liveSocket.isConnected());
  await expect(page.locator(".phx-connected").first()).toBeAttached();
}

async function clickUntil(page, name, appears) {
  await expect(async () => {
    if (await appears.isVisible()) return;

    await page.getByRole("button", { name }).first().click({ timeout: 3000 });
    await expect(appears).toBeVisible({ timeout: 3000 });
  }).toPass({ timeout: 60_000 });
}

async function signListing(page, method, listing) {
  await page.goto("/");
  await connected(page);
  await clickUntil(page, "+ New", page.locator("#new-listing"));

  await page.locator('#new-listing input[name="address"]').fill(listing.address);
  await page.locator('#new-listing input[name="suburb"]').fill(listing.suburb);
  await page.locator('#new-listing select[name="jurisdiction"]').selectOption(listing.jurisdiction);
  await page.locator('#new-listing select[name="sale_method"]').selectOption(method);
  await page.locator('#new-listing input[name="vendor_name"]').fill(listing.vendor);
  await page.locator('#new-listing input[name="guide_price_dollars"]').fill(listing.guide);
  await page.locator('#new-listing input[name="commission_rate"]').fill("2.2");

  await page.getByRole("button", { name: "Sign and put to market" }).click();

  await expect(page.getByRole("heading", { level: 1 })).toHaveText(listing.address);
}

async function clearCompliance(page) {
  await expect(page.getByRole("heading", { name: "Waiting on the vendor's solicitor" })).toBeVisible();

  const ready = page.getByRole("heading", { name: "Ready to go to market" });
  const deadline = Date.now() + 180_000;

  while (!(await ready.isVisible())) {
    if (Date.now() > deadline) throw new Error("the compliance gate never cleared");

    const document = page.getByRole("button", { name: /received$/ }).first();

    if (!(await document.isVisible())) {
      await page.waitForTimeout(500);
      continue;
    }

    const label = (await document.textContent()).trim();

    await document.click().catch(() => {});

    await page
      .getByRole("button", { name: label })
      .waitFor({ state: "hidden", timeout: 20_000 })
      .catch(() => {});
  }
}

async function takeOffer(page, buyer, lender, amount) {
  await page.locator('#new-offer input[name="buyer_name"]').fill(buyer);
  await page.locator('#new-offer input[name="lender"]').fill(lender);
  await page.locator('#new-offer input[name="amount_dollars"]').fill(amount);
  await page.getByRole("button", { name: "Take the offer" }).click();

  await expect(page.getByRole("cell", { name: buyer })).toBeVisible();
}

async function answerEveryBuyer(page) {
  const chooser = page.getByRole("heading", { name: "Choose the buyer" });

  await expect(async () => {
    if (await chooser.isVisible()) return;

    const accept = page.getByRole("button", { name: /^Accept / }).first();

    if (await accept.isVisible()) await accept.click({ timeout: 3000 });

    await expect(chooser).toBeVisible({ timeout: 3000 });
  }).toPass({ timeout: 90_000 });
}

const setDate = {
  address: anAddress("Ashworth Lane"),
  suburb: "Randwick",
  jurisdiction: "nsw",
  vendor: "H. Marchetti",
  guide: "1250000",
};

const auction = {
  address: anAddress("Kelburn Street"),
  suburb: "Fitzroy North",
  jurisdiction: "vic",
  vendor: "D. Okonjo",
  guide: "1400000",
};

async function resolveConditions(page) {
  const due = page.getByRole("heading", { name: /^Settlement due/ });
  const deadline = Date.now() + 180_000;

  const answers = [
    "Lender approves finance",
    "Building & pest report accepted",
    "Title search comes back clear",
  ];

  while (!(await due.isVisible())) {
    if (Date.now() > deadline) throw new Error("the conditions never cleared");

    for (const answer of answers) {
      const button = page.getByRole("button", { name: answer });

      if (await button.isVisible()) await button.click({ timeout: 5000 }).catch(() => {});
    }

    await page.waitForTimeout(1500);
  }
}

test("a set date sale runs from signing the vendor up to settlement", async ({ page }) => {
  await signListing(page, "set_date", setDate);
  await clearCompliance(page);

  await clickUntil(page, "Launch the campaign", page.getByRole("heading", { name: "Offers are open" }));

  await takeOffer(page, "Ferreira", "Kestrel Mutual", "1265000");
  await takeOffer(page, "Adeyemi", "cash", "1310000");

  await clickUntil(page, "Close offers now", page.getByRole("heading", { name: "Work the offers" }));

  await answerEveryBuyer(page);

  await clickUntil(page, /^Accept Adeyemi at/, page.getByRole("heading", { name: /^Cooling off/ }));

  await expect(page.getByRole("heading", { name: "Conditions to satisfy" })).toBeVisible({
    timeout: 90_000,
  });

  await resolveConditions(page);

  await expect(page.getByRole("heading", { name: /^Settlement due/ })).toBeVisible({
    timeout: 90_000,
  });

  await clickUntil(page, "Settlement completes", page.getByRole("heading", { name: "Settled" }));
  await expect(page.getByText("Paid to date")).toBeVisible();
});

test("an auction that passes in is negotiated with the underbidder", async ({ page }) => {
  await signListing(page, "auction", auction);
  await clearCompliance(page);

  await clickUntil(
    page,
    "Launch the campaign",
    page.getByRole("heading", { name: /Auction day|Negotiating|Choose the buyer/ }),
  );

  await takeOffer(page, "Bianchi", "Yarra Mutual", "1385000");

  await clickUntil(
    page,
    "Passed in",
    page.getByRole("heading", { name: /Negotiating|Choose the buyer/ }),
  );

  await answerEveryBuyer(page);

  await clickUntil(page, /^Accept Bianchi at/, page.getByRole("heading", { name: /^Cooling off/ }));

  await expect(page.getByText("Bianchi")).toBeVisible();
});
