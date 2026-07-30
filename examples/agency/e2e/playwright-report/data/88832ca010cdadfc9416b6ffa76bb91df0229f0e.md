# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: sale.spec.js >> a set date sale runs from signing the vendor up to settlement
- Location: tests/sale.spec.js:128:5

# Error details

```
Error: the compliance gate never cleared
```

# Page snapshot

```yaml
- generic [ref=e2]:
  - generic [ref=e3]:
    - generic [ref=e4]:
      - generic [ref=e5]: Ray & Cole
      - generic [ref=e6]: Sales desk
    - navigation [ref=e7]:
      - link "Sales desk" [ref=e8] [cursor=pointer]:
        - /url: /
      - link "Workflow console" [ref=e9] [cursor=pointer]:
        - /url: /console
    - generic [ref=e10]:
      - generic [ref=e11]: PR
      - generic [ref=e12]: Priya Chandra · Sales agent
  - generic [ref=e13]:
    - navigation [ref=e14]:
      - generic [ref=e15]:
        - generic [ref=e16]: My listings
        - button "+ New" [ref=e17] [cursor=pointer]
      - generic [ref=e18]:
        - button "14 Kurraba Road Neutral Bay · NSW · Set date sale $1,350,000 guide Offers open" [ref=e19] [cursor=pointer]:
          - generic [ref=e20]: 14 Kurraba Road
          - generic [ref=e21]: Neutral Bay · NSW · Set date sale
          - generic [ref=e22]:
            - generic [ref=e23]: $1,350,000 guide
            - generic [ref=e24]: Offers open
        - button "22 Ardoyne Road Corinda · QLD · Private treaty $890,000 guide Under contract" [ref=e25] [cursor=pointer]:
          - generic [ref=e26]: 22 Ardoyne Road
          - generic [ref=e27]: Corinda · QLD · Private treaty
          - generic [ref=e28]:
            - generic [ref=e29]: $890,000 guide
            - generic [ref=e30]: Under contract
        - button "51 Marine Parade Manly · NSW · Set date sale $2,400,000 guide Back on market" [ref=e31] [cursor=pointer]:
          - generic [ref=e32]: 51 Marine Parade
          - generic [ref=e33]: Manly · NSW · Set date sale
          - generic [ref=e34]:
            - generic [ref=e35]: $2,400,000 guide
            - generic [ref=e36]: Back on market
        - button "584 Ashworth Lane Randwick · NSW · Set date sale $1,250,000 guide Preparing" [ref=e37] [cursor=pointer]:
          - generic [ref=e38]: 584 Ashworth Lane
          - generic [ref=e39]: Randwick · NSW · Set date sale
          - generic [ref=e40]:
            - generic [ref=e41]: $1,250,000 guide
            - generic [ref=e42]: Preparing
        - button "636 Ashworth Lane Randwick · NSW · Set date sale $1,250,000 guide Preparing" [ref=e43] [cursor=pointer]:
          - generic [ref=e44]: 636 Ashworth Lane
          - generic [ref=e45]: Randwick · NSW · Set date sale
          - generic [ref=e46]:
            - generic [ref=e47]: $1,250,000 guide
            - generic [ref=e48]: Preparing
        - button "642 Kelburn Street Fitzroy North · VIC · Auction $1,400,000 guide Preparing" [ref=e49] [cursor=pointer]:
          - generic [ref=e50]: 642 Kelburn Street
          - generic [ref=e51]: Fitzroy North · VIC · Auction
          - generic [ref=e52]:
            - generic [ref=e53]: $1,400,000 guide
            - generic [ref=e54]: Preparing
        - button "8 Rialto Street Fitzroy North · VIC · Auction $1,200,000 guide Auction" [ref=e55] [cursor=pointer]:
          - generic [ref=e56]: 8 Rialto Street
          - generic [ref=e57]: Fitzroy North · VIC · Auction
          - generic [ref=e58]:
            - generic [ref=e59]: $1,200,000 guide
            - generic [ref=e60]: Auction
    - main [ref=e61]:
      - generic [ref=e62]:
        - generic [ref=e63]:
          - generic [ref=e64]: Randwick · New South Wales · Set date sale
          - heading "584 Ashworth Lane" [level=1] [ref=e65]
          - generic [ref=e66]: Vendor H. Marchetti · 2.2% inc GST, payable on settlement
        - generic [ref=e67]:
          - generic [ref=e68]: $1,250,000
          - generic [ref=e69]: guide
      - generic [ref=e70]:
        - generic [ref=e71]: Prepared
        - generic [ref=e73]: Offers
        - generic [ref=e75]: Exchanged
        - generic [ref=e77]: Cooling off
        - generic [ref=e79]: Conditions
        - generic [ref=e81]: Settled
      - generic [ref=e83]:
        - heading "Waiting on the vendor's solicitor" [level=3] [ref=e85]
        - generic [ref=e86]: The property can't go to market until the required documents arrive.
    - complementary [ref=e88]:
      - generic [ref=e89]:
        - generic [ref=e90]:
          - generic [ref=e91]: Your commission
          - generic [ref=e92]: 2.2%
        - generic [ref=e93]:
          - generic [ref=e94]: $27,500
          - generic [ref=e95]: Estimated at the guide price
        - generic [ref=e96]:
          - generic [ref=e97]: Sale price
          - generic [ref=e98]: —
        - generic [ref=e99]:
          - generic [ref=e100]: Deposit in trust
          - generic [ref=e101]: —
        - generic [ref=e102]:
          - generic [ref=e103]: Paid to date
          - generic [ref=e104]: —
        - generic [ref=e105]:
          - generic [ref=e106]: Written back
          - generic [ref=e107]: —
        - generic [ref=e108]:
          - generic [ref=e109]: Forfeited to vendor
          - generic [ref=e110]: —
      - generic [ref=e111]:
        - generic [ref=e112]:
          - generic [ref=e113]: NSW requirements
          - generic [ref=e114]: 0 of 4
        - generic [ref=e115]:
          - generic [ref=e116]:
            - generic [ref=e117]: "[ ]"
            - generic [ref=e118]: Contract of sale prepared
          - generic [ref=e119]:
            - generic [ref=e120]: "[ ]"
            - generic [ref=e121]: Title search
          - generic [ref=e122]:
            - generic [ref=e123]: "[ ]"
            - generic [ref=e124]: Drainage diagram
          - generic [ref=e125]:
            - generic [ref=e126]: "[ ]"
            - generic [ref=e127]: Planning certificate
        - generic [ref=e128]:
          - generic [ref=e129]:
            - text: Cooling off
            - generic [ref=e130]: from exchange
          - generic [ref=e131]: 5 bus. days
        - generic [ref=e132]:
          - generic [ref=e133]: Forfeit on rescission
          - generic [ref=e134]: 0.25%
      - generic [ref=e135]:
        - generic [ref=e136]: Activity
        - list
        - paragraph [ref=e138]: Nothing recorded yet.
```

# Test source

```ts
  1   | import { test, expect } from "@playwright/test";
  2   | 
  3   | function anAddress(street) {
  4   |   return `${Math.floor(Math.random() * 900) + 1} ${street}`;
  5   | }
  6   | 
  7   | async function connected(page) {
  8   |   await page.waitForFunction(() => window.liveSocket && window.liveSocket.isConnected());
  9   |   await expect(page.locator(".phx-connected").first()).toBeAttached();
  10  | }
  11  | 
  12  | async function clickUntil(page, name, appears) {
  13  |   await expect(async () => {
  14  |     if (await appears.isVisible()) return;
  15  | 
  16  |     await page.getByRole("button", { name }).first().click({ timeout: 3000 });
  17  |     await expect(appears).toBeVisible({ timeout: 3000 });
  18  |   }).toPass({ timeout: 60_000 });
  19  | }
  20  | 
  21  | async function signListing(page, method, listing) {
  22  |   await page.goto("/");
  23  |   await connected(page);
  24  |   await clickUntil(page, "+ New", page.locator("#new-listing"));
  25  | 
  26  |   await page.locator('#new-listing input[name="address"]').fill(listing.address);
  27  |   await page.locator('#new-listing input[name="suburb"]').fill(listing.suburb);
  28  |   await page.locator('#new-listing select[name="jurisdiction"]').selectOption(listing.jurisdiction);
  29  |   await page.locator('#new-listing select[name="sale_method"]').selectOption(method);
  30  |   await page.locator('#new-listing input[name="vendor_name"]').fill(listing.vendor);
  31  |   await page.locator('#new-listing input[name="guide_price_dollars"]').fill(listing.guide);
  32  |   await page.locator('#new-listing input[name="commission_rate"]').fill("2.2");
  33  | 
  34  |   await page.getByRole("button", { name: "Sign and put to market" }).click();
  35  | 
  36  |   await expect(page.getByRole("heading", { level: 1 })).toHaveText(listing.address);
  37  | }
  38  | 
  39  | async function clearCompliance(page) {
  40  |   await expect(page.getByRole("heading", { name: "Waiting on the vendor's solicitor" })).toBeVisible();
  41  | 
  42  |   const ready = page.getByRole("heading", { name: "Ready to go to market" });
  43  |   const deadline = Date.now() + 180_000;
  44  | 
  45  |   while (!(await ready.isVisible())) {
> 46  |     if (Date.now() > deadline) throw new Error("the compliance gate never cleared");
      |                                      ^ Error: the compliance gate never cleared
  47  | 
  48  |     const document = page.getByRole("button", { name: /received$/ }).first();
  49  | 
  50  |     if (!(await document.isVisible())) {
  51  |       await page.waitForTimeout(500);
  52  |       continue;
  53  |     }
  54  | 
  55  |     const label = (await document.textContent()).trim();
  56  | 
  57  |     await document.click().catch(() => {});
  58  | 
  59  |     await page
  60  |       .getByRole("button", { name: label })
  61  |       .waitFor({ state: "hidden", timeout: 20_000 })
  62  |       .catch(() => {});
  63  |   }
  64  | }
  65  | 
  66  | async function takeOffer(page, buyer, lender, amount) {
  67  |   await page.locator('#new-offer input[name="buyer_name"]').fill(buyer);
  68  |   await page.locator('#new-offer input[name="lender"]').fill(lender);
  69  |   await page.locator('#new-offer input[name="amount_dollars"]').fill(amount);
  70  |   await page.getByRole("button", { name: "Take the offer" }).click();
  71  | 
  72  |   await expect(page.getByRole("cell", { name: buyer })).toBeVisible();
  73  | }
  74  | 
  75  | async function answerEveryBuyer(page) {
  76  |   const chooser = page.getByRole("heading", { name: "Choose the buyer" });
  77  | 
  78  |   await expect(async () => {
  79  |     if (await chooser.isVisible()) return;
  80  | 
  81  |     const accept = page.getByRole("button", { name: /^Accept / }).first();
  82  | 
  83  |     if (await accept.isVisible()) await accept.click({ timeout: 3000 });
  84  | 
  85  |     await expect(chooser).toBeVisible({ timeout: 3000 });
  86  |   }).toPass({ timeout: 90_000 });
  87  | }
  88  | 
  89  | const setDate = {
  90  |   address: anAddress("Ashworth Lane"),
  91  |   suburb: "Randwick",
  92  |   jurisdiction: "nsw",
  93  |   vendor: "H. Marchetti",
  94  |   guide: "1250000",
  95  | };
  96  | 
  97  | const auction = {
  98  |   address: anAddress("Kelburn Street"),
  99  |   suburb: "Fitzroy North",
  100 |   jurisdiction: "vic",
  101 |   vendor: "D. Okonjo",
  102 |   guide: "1400000",
  103 | };
  104 | 
  105 | async function resolveConditions(page) {
  106 |   const due = page.getByRole("heading", { name: /^Settlement due/ });
  107 |   const deadline = Date.now() + 180_000;
  108 | 
  109 |   const answers = [
  110 |     "Lender approves finance",
  111 |     "Building & pest report accepted",
  112 |     "Title search comes back clear",
  113 |   ];
  114 | 
  115 |   while (!(await due.isVisible())) {
  116 |     if (Date.now() > deadline) throw new Error("the conditions never cleared");
  117 | 
  118 |     for (const answer of answers) {
  119 |       const button = page.getByRole("button", { name: answer });
  120 | 
  121 |       if (await button.isVisible()) await button.click({ timeout: 5000 }).catch(() => {});
  122 |     }
  123 | 
  124 |     await page.waitForTimeout(1500);
  125 |   }
  126 | }
  127 | 
  128 | test("a set date sale runs from signing the vendor up to settlement", async ({ page }) => {
  129 |   await signListing(page, "set_date", setDate);
  130 |   await clearCompliance(page);
  131 | 
  132 |   await clickUntil(page, "Launch the campaign", page.getByRole("heading", { name: "Offers are open" }));
  133 | 
  134 |   await takeOffer(page, "Ferreira", "Kestrel Mutual", "1265000");
  135 |   await takeOffer(page, "Adeyemi", "cash", "1310000");
  136 | 
  137 |   await clickUntil(page, "Close offers now", page.getByRole("heading", { name: "Work the offers" }));
  138 | 
  139 |   await answerEveryBuyer(page);
  140 | 
  141 |   await clickUntil(page, /^Accept Adeyemi at/, page.getByRole("heading", { name: /^Cooling off/ }));
  142 | 
  143 |   await expect(page.getByRole("heading", { name: "Conditions to satisfy" })).toBeVisible({
  144 |     timeout: 90_000,
  145 |   });
  146 | 
```