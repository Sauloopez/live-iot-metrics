// Reading definitions and readings: free-text sensor types with suggestions and validation,
// a reading started from the dashboard, the delete dialogs (Escape cancels, a definition in use
// is blocked) and deleting a reading and then its definition.
import { BASE_URL, checker, launch, shot } from "./support.mjs";

const RUN = Date.now();
const DEFINITION = `e2e-definition-${RUN}`;
const AREA = `e2e-area-${RUN}`;
const READING = `e2e-reading-${RUN}`;
const t = checker("Reading definitions and readings");
const { browser, page, errors } = await launch({
  viewport: { width: 1300, height: 950 },
});

// --- Create a definition with a free-text type ---
await page.goto(`${BASE_URL}/recipes`);
await page.click("#btn-add-recipe");
const type = page.locator(
  "input[name='recipe[property_ranges][0][sensor_type]']",
);
await type.waitFor();
t.check(
  "type input offers suggestions",
  (await type.getAttribute("list")) === "recipe-sensor-types",
);
const suggestions = await page
  .locator("#recipe-sensor-types option")
  .evaluateAll((els) => els.map((e) => e.value));
t.check(
  "suggestions include preset types",
  suggestions.includes("soil_moisture"),
  suggestions.join(", "),
);

await page.fill("input[name='recipe[name]']", DEFINITION);
await type.fill("bad type!");
await page.fill("input[name='recipe[property_ranges][0][min_value]']", "40");
await page.fill("input[name='recipe[property_ranges][0][max_value]']", "80");
await page
  .getByText("lowercase letters, numbers and underscores")
  .waitFor({ timeout: 3000 });
t.check("invalid type shows a validation error", true);

await type.fill("  Soil_Moisture ");
await page.fill("input[name='recipe[property_ranges][0][min_value]']", "40.5");
await page.click("#recipe-form button[type=submit]");
const definitionRow = page.locator("#recipes_table tr", {
  hasText: DEFINITION,
});
await definitionRow.waitFor();
t.check(
  "definition saved with the normalized type",
  (await definitionRow.innerText()).includes("soil_moisture"),
);

// --- Delete dialog: Escape cancels ---
await definitionRow.locator("[id^=delete-recipe-]").click();
await page.waitForSelector("#delete-recipe-dialog");
await page.keyboard.press("Escape");
await page.waitForSelector("#delete-recipe-dialog", { state: "detached" });
t.check(
  "Escape closes the dialog without deleting",
  await definitionRow.isVisible(),
);

// --- Start a reading of that definition ---
await page.goto(`${BASE_URL}/`);
await page.click("#btn-add-area");
await page.fill("#add-area-form input[name=name]", AREA);
await page.fill(
  "#add-area-form textarea[name=description]",
  "Created by the e2e tests",
);
await page.click("#add-area-form button[type=submit]");
await page.locator("[id^=area-tab-]", { hasText: AREA }).waitFor();
await page.click("#btn-start-batch");
await page.fill("#start-batch-form input[name='recipe_batch[name]']", READING);
await page.selectOption(
  "#start-batch-form select[name='recipe_batch[recipe_id]']",
  { label: DEFINITION },
);
await page.click("#start-batch-form button[type=submit]");
const card = page.locator("[id^=batch-card-]", { hasText: READING });
await card.waitFor();
t.check("reading started from the dashboard", true);

// --- A definition in use can not be deleted ---
await page.goto(`${BASE_URL}/recipes`);
await definitionRow.locator("[id^=delete-recipe-]").click();
await page.waitForSelector("#delete-recipe-dialog");
t.check(
  "definition in use is blocked",
  !(await page.isVisible("#delete-recipe-dialog-confirm")),
);
t.check(
  "blocked dialog lists the reading",
  (await page.innerText("#recipe-batches-in-use")).includes(READING),
);
await shot(page, "definitions-blocked");

// --- Open the reading from the dialog and delete it ---
await page
  .locator("#recipe-batches-in-use [id^=open-recipe-batch-]")
  .first()
  .click();
await page.waitForSelector("#btn-delete-batch");
await page.click("#btn-delete-batch");
await page.waitForSelector("#delete-batch-dialog");
await shot(page, "definitions-delete-reading");
await page.click("#delete-batch-dialog-confirm");
await page.waitForURL(`${BASE_URL}/`);
t.check("reading deleted, back on the dashboard", true);

// --- Now the definition can be deleted ---
await page.goto(`${BASE_URL}/recipes`);
await definitionRow.locator("[id^=delete-recipe-]").click();
await page.click("#delete-recipe-dialog-confirm");
await definitionRow.waitFor({ state: "detached" });
t.check("definition deleted once unused", true);

await t.finish(browser, errors);
