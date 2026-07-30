# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: sale.spec.js >> an auction that passes in is negotiated with the underbidder
- Location: tests/sale.spec.js:157:5

# Error details

```
Error: locator.click: Timeout 3000ms exceeded.
Call log:
  - waiting for getByRole('button', { name: /^Accept Bianchi at/ }).first()


Call Log:
- Timeout 60000ms exceeded while waiting on the predicate
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
        - button "226 Kelburn Street Fitzroy North · VIC · Auction $1,400,000 guide Preparing" [ref=e31] [cursor=pointer]:
          - generic [ref=e32]: 226 Kelburn Street
          - generic [ref=e33]: Fitzroy North · VIC · Auction
          - generic [ref=e34]:
            - generic [ref=e35]: $1,400,000 guide
            - generic [ref=e36]: Preparing
        - button "51 Marine Parade Manly · NSW · Set date sale $2,400,000 guide Back on market" [ref=e37] [cursor=pointer]:
          - generic [ref=e38]: 51 Marine Parade
          - generic [ref=e39]: Manly · NSW · Set date sale
          - generic [ref=e40]:
            - generic [ref=e41]: $2,400,000 guide
            - generic [ref=e42]: Back on market
        - button "584 Ashworth Lane Randwick · NSW · Set date sale $1,250,000 guide Preparing" [ref=e43] [cursor=pointer]:
          - generic [ref=e44]: 584 Ashworth Lane
          - generic [ref=e45]: Randwick · NSW · Set date sale
          - generic [ref=e46]:
            - generic [ref=e47]: $1,250,000 guide
            - generic [ref=e48]: Preparing
        - button "636 Ashworth Lane Randwick · NSW · Set date sale $1,250,000 guide Preparing" [ref=e49] [cursor=pointer]:
          - generic [ref=e50]: 636 Ashworth Lane
          - generic [ref=e51]: Randwick · NSW · Set date sale
          - generic [ref=e52]:
            - generic [ref=e53]: $1,250,000 guide
            - generic [ref=e54]: Preparing
        - button "642 Kelburn Street Fitzroy North · VIC · Auction $1,400,000 guide Preparing" [ref=e55] [cursor=pointer]:
          - generic [ref=e56]: 642 Kelburn Street
          - generic [ref=e57]: Fitzroy North · VIC · Auction
          - generic [ref=e58]:
            - generic [ref=e59]: $1,400,000 guide
            - generic [ref=e60]: Preparing
        - button "8 Rialto Street Fitzroy North · VIC · Auction $1,200,000 guide Auction" [ref=e61] [cursor=pointer]:
          - generic [ref=e62]: 8 Rialto Street
          - generic [ref=e63]: Fitzroy North · VIC · Auction
          - generic [ref=e64]:
            - generic [ref=e65]: $1,200,000 guide
            - generic [ref=e66]: Auction
    - main [ref=e67]:
      - generic [ref=e68]:
        - generic [ref=e69]:
          - generic [ref=e70]: Fitzroy North · Victoria · Auction
          - heading "226 Kelburn Street" [level=1] [ref=e71]
          - generic [ref=e72]: Vendor D. Okonjo · 2.2% inc GST, payable on settlement
        - generic [ref=e73]:
          - generic [ref=e74]: $1,400,000
          - generic [ref=e75]: guide
      - generic [ref=e76]:
        - generic [ref=e77]: Prepared
        - generic [ref=e79]: Auction
        - generic [ref=e81]: Exchanged
        - generic [ref=e83]: Cooling off
        - generic [ref=e85]: Conditions
        - generic [ref=e87]: Settled
      - generic [ref=e89]:
        - generic [ref=e90]:
          - heading "Auction day" [level=3] [ref=e91]
          - generic [ref=e92]: Needs you
        - generic [ref=e93]:
          - generic [ref=e94]: "Highest bid on record: $1,385,000."
          - generic [ref=e95]:
            - button "Sold under the hammer at $1,385,000" [ref=e96] [cursor=pointer]
            - button "Passed in" [ref=e97] [cursor=pointer]
          - generic [ref=e98]:
            - textbox "Buyer" [ref=e99]
            - textbox "Lender, or cash" [ref=e100]
            - textbox "Offer" [ref=e101]
            - button "Take the offer" [ref=e102] [cursor=pointer]
      - generic [ref=e103]:
        - heading "Registered bidders" [level=3] [ref=e105]
        - table [ref=e107]:
          - rowgroup [ref=e108]:
            - row [ref=e109]:
              - columnheader "Buyer" [ref=e110]
              - columnheader "Amount" [ref=e111]
              - columnheader "Position" [ref=e112]
          - rowgroup [ref=e113]:
            - row [ref=e114]:
              - cell "Bianchi Yarra Mutual" [ref=e115]:
                - generic [ref=e116]: Bianchi
                - generic [ref=e117]: Yarra Mutual
              - cell "$1,385,000" [ref=e118]
              - cell "Offer on the table" [ref=e119]
    - complementary [ref=e120]:
      - generic [ref=e121]:
        - generic [ref=e122]:
          - generic [ref=e123]: Your commission
          - generic [ref=e124]: 2.2%
        - generic [ref=e125]:
          - generic [ref=e126]: $30,800
          - generic [ref=e127]: Estimated at the guide price
        - generic [ref=e128]:
          - generic [ref=e129]: Sale price
          - generic [ref=e130]: —
        - generic [ref=e131]:
          - generic [ref=e132]: Deposit in trust
          - generic [ref=e133]: —
        - generic [ref=e134]:
          - generic [ref=e135]: Paid to date
          - generic [ref=e136]: —
        - generic [ref=e137]:
          - generic [ref=e138]: Written back
          - generic [ref=e139]: —
        - generic [ref=e140]:
          - generic [ref=e141]: Forfeited to vendor
          - generic [ref=e142]: —
      - generic [ref=e143]:
        - generic [ref=e144]:
          - generic [ref=e145]: VIC requirements
          - generic [ref=e146]: 3 of 3
        - generic [ref=e147]:
          - generic [ref=e148]:
            - generic [ref=e149]: "[x]"
            - generic [ref=e150]: Vendor statement
          - generic [ref=e151]:
            - generic [ref=e152]: "[x]"
            - generic [ref=e153]: Statement of information
          - generic [ref=e154]:
            - generic [ref=e155]: "[x]"
            - generic [ref=e156]: Title search
        - generic [ref=e157]:
          - generic [ref=e158]:
            - text: Cooling off
            - generic [ref=e159]: not applicable at auction
          - generic [ref=e160]: 3 bus. days
        - generic [ref=e161]:
          - generic [ref=e162]: Forfeit on rescission
          - generic [ref=e163]: 0.2%
      - generic [ref=e164]:
        - generic [ref=e165]: Activity
        - list [ref=e167]:
          - listitem [ref=e168]:
            - time [ref=e169]: 30 Jul 2026
            - generic [ref=e170]: Received the title search
          - listitem [ref=e171]:
            - time [ref=e172]: 30 Jul 2026
            - generic [ref=e173]: Received the statement of information
          - listitem [ref=e174]:
            - time [ref=e175]: 30 Jul 2026
            - generic [ref=e176]: Received the vendor statement
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
> 18  |   }).toPass({ timeout: 60_000 });
      |      ^ Error: locator.click: Timeout 3000ms exceeded.
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
  46  |     if (Date.now() > deadline) throw new Error("the compliance gate never cleared");
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
```