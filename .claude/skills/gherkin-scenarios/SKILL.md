---
name: "gherkin-scenarios"
description: "Use when writing, reviewing or refactoring Gherkin (Given/When/Then) scenarios or .feature files for UI, API or backend tests: short scenarios, one state, one case per scenario."
---

# Writing Gherkin scenarios

A feature file is a test plan. The reviewer must read each scenario and know, without asking: where the system starts, what single thing happens, what is checked, where each piece of data comes from, and why this scenario exists apart from its neighbours.

## Terms used in this skill

The rules apply to any interface: a web or mobile UI, an API, or a backend process with no UI (a queue consumer, a batch job, a command). The **interface under test** is the one the When acts on.

| Term | Meaning | In a UI | In an API | In a backend process |
|---|---|---|---|---|
| **Entry point** | What the When acts on | A button, link or form | An operation on a resource | A message, job or command |
| **Module** | One observable output; what the Thens check | A table, dialog or summary message | The response | A published message, an output file |
| **Interface detail** | How an output is presented, not what it means | Texts, enabled or disabled controls, empty states | Exact status code, error body, field formats | Message format, log text |
| **Stored state** | What persists after the When, read through the system's own read interface | | | |

## How much of this to apply

- **A new feature file:** all five phases, in order.
- **A few scenarios in an existing file:** read its header, vocabulary and steps (1.2, 1.5); plan the new cases (Phase 2); write (Phase 4); run the Phase 5 checklist on what you touched.
- **Reviewing a file:** change nothing first. Run the Phase 5 checklist, report each finding with its scenario and the rule it breaks, then propose the fixes.

---

## Phase 1 · Prepare

### 1.1 Read the sources and list the open decisions
Read the specs, decisions, mock-ups or contracts the feature comes from. Planning cases exposes behaviour nobody decided yet (an archived record, invalid external data...). **Do not invent the answer, and do not write a scenario for it.** List each one as an open question and ask before planning the cases that depend on it. If you propose an answer, say it is a proposal. Two sources that contradict each other are an open question too.

### 1.2 Write the vocabulary
In the feature's header comment (F.1), define every domain term the steps will use. One term, one meaning:
- If a word could name two states, split it. *Bad:* "the connected supplier" for both "linked to its feed" and "its catalogue was already imported". *Good:* "the supplier" (always linked, said once) and "its catalogue was already imported" (said only where it matters).
- Define every shorthand used in steps ("with all its data" = exactly which fields).
- Define every comparison rule the system applies (2.5).

### 1.3 Map where each piece of data lives
**Applies when** the same kind of data can live in more than one place (a master record and a per-context copy, a draft and a published version...).
Write down which store owns which field and, in the vocabulary, through which read interface each store is read. Every step that mentions such data names its source ("the price in the order", "the price in the catalogue").

### 1.4 Know the shape of the interface
Before writing steps, know what the interface under test offers: in a UI, which screens are full pages and which are dialogs, and the controls of each; in an API, the operations and what each returns on success and on each error; in a backend process, what comes in and what comes out.
Steps name these elements as their consumer sees them (4.9).

### 1.5 Read the existing steps
Before inventing a step, look for an existing one that says the same: the same situation is always written with the same words. Keep the voice the project already uses (first person or a named actor) and never mix the two in one file.
If existing steps break this skill (a When that prepares and acts, literal data), new scenarios follow the skill and keep the project's voice and vocabulary. Do not rewrite the old ones; report them when handing over.
The project's own test guidelines (which common states each screen or operation gets, which tags) win over this skill's defaults; say so in the header.

---

## Phase 2 · Plan the cases

### 2.1 Partition by the unit the rule applies to
Find the unit the behaviour depends on (each item, each record, each field, the whole list) and split the cases by it. A condition about another unit is not a case. *Example:* if an import decides product by product, "the catalogue is empty" is not a case; "the product is unknown / known / known twice / discontinued" are.

### 2.2 No general scenario that is not true for every item
Never write "doing X does Y to all items" if some items behave differently. Write one scenario per class of item, each with a Given that puts the item in that class.
**The same for anything that only happens with certain data** (a warning, a lock, a notification): write also **one** case in which it does not happen, the nearest one, with a Then that checks it did not.

### 2.3 Preconditions: every one that matters, none that does not
- State every condition that changes the outcome.
- Remove every condition the scenario does not depend on ("empty", "never imported", "of the current year"...). **Test:** delete the condition; if no Then could change, it goes. What the vocabulary states as the default is never repeated in a Given.
- **A condition that keeps random data inside the intended class does matter**: without it the data can fall into another case. *Bad:* `Given the supplier publishes a catalogue`. *Good:* `Given the supplier publishes a catalogue with only products the shop does not have`.

### 2.4 Every starting state must be reachable
A Given may only set up a state the system can really be in:
- **States the system produces itself** (two customers with the same name): the flow that produces them has its own scenario somewhere; if not, add it.
- **States from outside** (an external service that fails, is slow or sends odd data): the fake of that service produces them.
- If nothing can produce the state, drop the scenario or question the spec.

### 2.5 Define the comparison rule, then test each aspect
**Applies when** the behaviour depends on two values being "the same" (matching, deduplication).
Write the normalization in the vocabulary (case, surrounding spaces, punctuation, leading zeros...). Cover the aspects that must match with one outline (2.9), one row per aspect the sources name, **and the cases that must not match in a separate scenario or outline** (2.6). When the difference can be on either side compared, give one aspect a row in each direction. A search is not a comparison and may be more lenient: one scenario combining the aspects.

### 2.6 One Scenario Outline for the cases of one rule
When cases share Given, When and Then and differ only in a value or a category, write one outline, one class per Examples row. **Put a parameter in the title**, so each row is named in the report (`Scenario Outline: A name <how> is not saved`).
- One rule per outline: no outline that joins several rules with a column saying which.
- A row that would change the wording of a step (another action, another place, another kind of check) or has the opposite outcome (it warns / it does not) is a separate scenario.
- No row or column for a dimension that does not change the outcome (the same case again for another period or another owner).

### 2.7 Merge scenarios that differ only in data, if they fit
If two scenarios have the same Given, When and checks and differ only in the data, keep one, with the data that would also catch the other's bug. If the merged scenario exceeds 7 steps, keep them apart, split by what each one checks.

### 2.8 Choose data that exposes a wrong implementation
**Applies when** a value could be read from the wrong place or computed the wrong way. Choose data on which the wrong implementation gives a different result: two stores with different values, a count other than 1, an order that is not the default one. Put that data in the Given of the scenario that already checks the value, **in every module that shows it** (the list, the detail, its at-rest scenario); no second scenario just to prove it.

### 2.9 Scenario or unit test
**Applies when** the behaviour is a pure rule with many combinations (formatting, validation, normalization, a data constraint such as uniqueness).
All the combinations go to unit tests. Scenarios keep **one** outline per rule, with the classes the sources name, or one representative case that combines several. Boundaries on the valid side and variants of a constraint are unit tests. **This rule wins over 2.5, 2.6 and P1** whenever they would add rows; at which entry points the outline appears is decided by 2.12.

### 2.10 Flow or detail
Decide by the When and the Thens together.
- **Flow:** the When writes or publishes (in a UI, also navigates), and **every** Then checks what was written, as data ("the order is cancelled"), or where the consumer ends up, even when that data is read in a table or a response.
- **Detail:** everything else: what a module shows or offers at rest, a message, a marker, a sort order, a count, an empty state, a control's state; without a UI, the exact status code, the error body, a field's format, a log line. One Then of this kind makes the whole scenario detail.
- **What a module offers at rest gets one detail scenario per module**, when the sources say it: in a UI, the actions each item has or the fields a form requires; in an API, what a resource advertises or the fields its schema requires. A backend process usually has none. Only there is an entry point's existence asserted, never in flow: the scenario whose When uses it fails anyway.
- **A rejection is one detail scenario**, which checks how the rejection is reported. No flow twin with the same Given and When. Add "nothing was stored" to that same scenario, as a read of stored state (4.3), only when a partial write is a real risk (an import or a batch that fails halfway).
- Check each fact once. Tag the two kinds with the project's own tags.

### 2.11 Patterns for common situations
Use the ones whose "Applies when" fits.

**P1 · Saving a record with required and optional fields**
*Applies when* an operation saves a record (a form, an endpoint, a command). The list is a ceiling: every case must pass 2.9 and 2.12. The saving cases are flow scenarios; their Thens follow 4.3.
- Only the required fields.
- Each optional field alone, the others empty (outline, one row per field).
- All the optional fields.
- Each required field missing (one outline), and each validation rule the sources name (one outline of invalid classes per rule). These are detail scenarios (2.10).
- *If the input comes prefilled* from an earlier record (an edit form, a partial update): changing one field of each store the save writes. Clearing a field, only if clearing does something a change does not. Nothing else: no "saving unchanged", no row per field.
- *If the input can be abandoned before saving* (a cancel, a discarded draft, a rolled-back batch): abandoning with data already entered stores nothing. One per entry point.

**P2 · Counters and summaries**
*Applies when* the outcome is an aggregate (counts, totals, a summary message), not a single item.
Counters can only be checked if the starting data and every input (external systems included) are under control: the content may be random, but the scenario fixes how many items of each class there are. Test them by **incremental states**, each built from the previous one:
1. **First time**, from an empty state never processed.
2. **Again, no changes**: the baseline; every counter except "unchanged" is zero.
3. **Again, one change of each kind**: one row per kind, so a wrong counter points to its cause.
4. **Again, the same change twice**: one row per kind, to see the counter add up.
5. Optionally, **two different changes together**.

Write **one** outline whose Examples hold the starting state, the inputs and the expected value of **every** counter, zeros included, so each row sees them all. If one Then per counter does not fit in 7 steps, group related counters in a Then (4.5); do not split the outline. Write counts relative to the generated data ("all", "none", "1", "the previous ones"). Whatever the summary says about one item by name gets its own scenario.

**P3 · Importing or synchronizing from an external source**
*Applies when* the system adds, matches or updates records from another system.
- A fake of the source serves exactly the data each scenario declares.
- Whole-list behaviour first: last sync date, never synced, source error, source slow.
- Then each item, partitioned (2.1): unknown; known (matched); known more than once; excluded by a rule (marked locally to be ignored, out of the range the sync takes, invalid data: see 2.12, question 2); already present (no duplicate, local edits kept); present locally but missing from the source.
- Then the summary, with P2.

**P4 · Read-only states**
*Applies when* a record can be locked (archived, closed, published). Ask whether "read-only" covers every action.
- In a UI: one detail scenario checks that every control that changes the record is gone or disabled.
- Without a UI: one outline, with one row per write operation, checks that each one is rejected.

### 2.12 Prune the case list
The rules and patterns above produce candidates, not obligations. Ask every case three questions; on a "no", drop it, or cut it down as question 2 says:
1. **Does a source decide it?** Behaviour nobody decided is an open question (1.1), not a scenario. Concurrent use included, unless a source asks for it. A case a pattern derives is decided when the sources make its *Applies when* true; if only its shape is unknown (which control or operation, where the error appears), that is an assumption (Phase 3), not an open question.
2. **Is this where its rule is tested in full?** A rule shared by several entry points (the same validation in a create and an update, in a form and an import) is tested in full at one: the one where its result is plainest (a plain rejection). The header of the others says where (F.1). Each other entry point gets:
   - **the classes again, in one outline, when either holds:** the data reaches it from another origin (another system or a file, not the same consumer through another screen or operation); or the rejection has another consequence there (a default replaces the value, the whole batch is held back), even when the same consumer enters the data;
   - **otherwise one representative case**: one, not zero and not the classes.
3. **Is it specific to this feature?** States and behaviours common to the whole system (loading, a generic server error, a malformed request, a retry policy, keyboard handling) are tested once in the project, not in every file.

---

## Phase 3 · Get the case list approved

Before writing any step, hand over **the list of scenario titles, grouped by block, in order**, with their tag (flow or detail), the outlines with their Examples rows, the open questions (1.1) and the vocabulary (1.2). Wait for approval: a wrong or missing case shows in the titles alone, where it is cheapest to fix.

If nobody is there to approve (an unattended run), do not stop, **and do not turn open questions into scenarios**: hand each one over as a question. Take an assumption only when a case the sources do ask for cannot be written without it: typically the shape of the interface (a control, a confirmation step, an operation's path, a message field) or the exact meaning of a counter. Name an assumed element by what it does (4.11); write the assumption in the header comment and mark the scenario that depends on it. Put the case list, questions and assumptions first in what you hand over.

---

## Phase 4 · Write

### 4.1 At most 7 steps
Count every step line; a complex step counts as one. If you need more, the scenario tests too much (split it) or needs complex Givens (4.6).

### 4.2 One system state: one Given → When → Then
Exactly one When, and it is **one interaction** with the named entry point (4.9): one press, one request, one message (typing into one field or choosing one file counts as one). Never When/Then/When/Then, and never a When that prepares and then acts ("I fill in the form and save"). What the consumer does before (opening, filling in, selecting) goes in Givens, in the past tense (4.6). The data a single request or message carries is part of that one interaction. A further action is a further state and a further scenario.

### 4.3 The Thens check one module, plus what it does not show
Assert on one module. Other modules get their own scenarios; repeating the Given and When there is fine.
**After a write**, the module's Thens check the written values where the consumer sees them (the fields of the row, of the response), not only that the item is there.
**Exception to "one module":** a Then may also read stored state through the system's own read interface. Use it only for what the module does not show (another store, a field not displayed): one Then per such store, which may group its fields (4.5). Give no new vocabulary term to a store the module already shows.

### 4.4 Givens reach state N−1, one When moves to N, Thens assess N
Each transition of a flow gets its own scenario(s), so a failure points to it.

### 4.5 Report every failure in the module (soft assertions)
One Then per item that can be checked on its own (each field, each column). Step definitions collect failures across the Thens and fail once at the end, listing them all.
**Applies when** one Then per value would exceed 7 steps (a summary with counters, the fields of one item): group related values in one Then, each value its own soft assertion, so a failure names which one. Splitting the values into two outlines is the last resort, because then no row sees them all.

### 4.6 Simple and complex Given steps
- Simple step: one action. `Given I enter a valid email in the email field`
- Complex step: several simple steps that reach a known state, named after that state. `Given I have completed the shipping step of checkout`

A complex step's inside is tested by its own scenarios. Prefer one complex Given that names the state over a chain of Givens that builds it.
A complex Given may include actions on the interface under test, in the past tense.
**A complex Given may use the operation under test** only when what is tested is a later application of it ("importing again"), and the first application has its own scenario.

### 4.7 Every step states where it starts
Its starting point is explicit in its wording or follows from the previous steps. No hidden technical prerequisites (clear a cache, wait, toggle a flag): a step that needs them does them in its implementation or in hooks.

### 4.8 A Then observes a state; it never acts
"The field can be changed" or "the order can be cancelled" hides an action: checking it means doing it. Write the observable state ("the order's status is open"; in a UI, "the field is enabled"). That it can be done is proven by the flow scenario whose When does it.

### 4.9 Name the concrete entry point
Name the entry point as its consumer sees it.
- UI: "I press the link to the orders" is not enough when the screen has several ways out. Name the element as shown: `When I press the link "← Orders of" and the customer's name, above the order detail`.
- Without a UI: name the operation or message as its consumer knows it, and say which one when several do similar things (cancelling a whole order or one of its lines).

### 4.10 The title names one result
One sentence with the one outcome the scenario exists for ("Changing a quantity updates the order total"). Check it:
- no "and" and no comma that joins a second result;
- what the other Thens also check stays out of the title;
- the place, the control or the operation appears only when it is what tells the scenario from its neighbour.

*Bad:* `Editing <field> from the row saves it in the order and in the catalogue, and stays on the list`. *Good:* `Editing the quantity changes it in the order`.
And the reverse: the title promises nothing the Thens do not check ("without warning" when no Then checks it). Rename it or add the Then.

### 4.11 Do not invent exact texts; list what you had to invent
Quote a text (a label, a message, an error code) only when the sources give it; a text given as an example counts; of a text with a variable part, quote the fixed part. If they give none, name the element by what it does and say what the output communicates, without quotes. *Bad:* `Then I see "The source returned an error. Try again later."` *Good:* `Then it says that the source did not answer and that the import can be retried`.
Whatever else the spec does not give (labels and empty states in a UI; status codes and field names in an API; message formats in a backend process) is a proposal; list them all when handing over.

---

## Data

### D.1 No hard-coded test data
Givens and Examples rows describe data by its characteristics, **also in comparisons and validations**: write the class (`with spaces the source does not have`, `longer than the maximum`), not a sample value. A literal is allowed only when the value itself decides the branch and no description is clearer: a boundary number, a format, a country that changes the flow. Sample names of people or products are never literals.

### D.2 Where the data comes from, in this order
1. Existing data, through the system's own read interface.
2. New data, through the system's own write interface, when none fits.
3. Direct database access, only as a last option.

Set up below the interface under test when you can: in a UI test, through the API and not through the screens. Do not use the operation under test to prepare its own scenario, except as allowed in 4.6.

### D.3 Random, within the class
Pick at random among the records of the class the scenario declares (2.3). Keep the chosen data in the scenario context so When and Then use the same values, and log it to reproduce a failing run.

---

## File organization

### F.1 Header comment
Each feature file starts with a short comment that has:
- its sources;
- what has no scenario, and why (unit tests, tested at another entry point or once in the project (2.12), impossible with the fake, out of scope): one line per reason, not per case;
- the vocabulary (1.2), including how each store is read (1.3);
- the rules it relies on and how the scenarios are ordered, only when the block headings do not already show them;
- the assumptions taken without approval, if any (Phase 3).

### F.2 Blocks and order
Group scenarios under block comments (`# ── Block ──`). Every scenario must fit its heading. Order the blocks from the general to the particular: whole-entity behaviour specific to the feature (in a UI, entering it); then the cases of each item, or each step of the flow, in the order a consumer meets them; aggregates (P2) after the cases they count; details last.

---

## Phase 5 · Review before delivering

**Each scenario**
- [ ] Has it 7 steps or fewer and one When that is a single interaction, everything before it in Givens (4.1, 4.2, 4.4)?
- [ ] Do the Thens check one module, the written values where the consumer sees them, reading below only what it does not show (4.3)?
- [ ] Is there one Then per item or per group of related values, each an observable state, never an action (4.5, 4.8)?
- [ ] Does the title name one result, with no "and" or comma joining a second, and promise nothing the Thens do not check (4.10)?
- [ ] Would deleting any one condition change a Then or let the data leave its class? Is none that matters missing (2.3)?
- [ ] Is the starting state reachable (2.4), every entry point named (4.9), and every value that lives in two places named with its source (1.3)?
- [ ] Is it flow only if the When writes, publishes or navigates and every Then checks what was written or where it leads? Is each rejection one detail scenario (2.10)?
- [ ] When a many-record write fails, does its scenario also check that nothing was stored (2.10)?
- [ ] Does every scenario showing a value stored in two places start from data where the two differ (2.8)?
- [ ] Is the data described by its class, every literal a value that decides the branch, and every quoted text given by the sources (D.1, 4.11)?
- [ ] Is the setup done through the system's own interfaces, not the operation under test (D.2), with existing step wordings (1.5)?

**Each file**
- [ ] Is the header short and complete (F.1), with one meaning per term (1.2) and any overriding project guideline (1.5)?
- [ ] Is every "for all items" scenario true for every item, and has each behaviour that needs certain data its nearest case without it (2.2)?
- [ ] Did every case pass 2.12: decided by a source or an applying pattern; its rule in full at one entry point, elsewhere the classes for another origin or consequence, else one case; specific to this feature?
- [ ] Is each pure rule in its own outline, with the classes the sources name and a parameter in the title, the non-matching cases apart, the rest in unit tests (2.5, 2.9)?
- [ ] Does every outline row change only a value, never a step's wording or the outcome's kind, and every column the outcome (2.6)?
- [ ] Is every pair that differs only in data merged or too long to merge (2.7)?
- [ ] Where the sources say what a module offers at rest, has it one detail scenario for it (2.10)?
- [ ] Is each case of the patterns that apply (P1–P4) present or pruned, with the counters in one outline whose rows see them all?
- [ ] Are the blocks in order, each scenario under a heading it fits (F.2)?

**When handing over**
- [ ] Was the case list approved before writing steps, or handed over with its questions and assumptions (Phase 3)?
- [ ] Is there no scenario for behaviour nobody decided, and is every assumption needed by a case the sources ask for?
- [ ] Are the open questions, the assumptions, what you invented (4.11) and the existing steps that break this skill (1.5) listed?

---

## Examples

### A general scenario that is not true → one per class (backend process)
Bad: `Scenario: The import adds every product of the supplier`
Good:
```gherkin
Scenario: A product the shop does not have is added
  Given the supplier publishes a product the shop does not have
  When the import job runs
  Then the catalogue has the new product
  And the new product has its name and no price
```
And one more per class: `A product the shop discontinued is not added again`.

### Data that does not say its source → named, and chosen to discriminate
Bad: `Given an order has a line with all its data` ... `Then the detail shows the line's price`
Good:
```gherkin
Given an order has a line with a price in the order different from the one in the catalogue
When I open the order detail
Then the detail shows the price in the order
```

### A When that prepares and acts → one interaction; written values where they are seen
The list shows the phone, so it is checked there; the address is not shown, so it is read below the UI ("the customer's record": what the customer lookup returns).
Bad: `When I create a new customer "ANA LOPEZ" with only the name and save`
Good:
```gherkin
Given in the new customer form I have filled in only the required fields
When I press "Save" in the new customer form
Then the customer list has the new customer
And the new customer's row has no phone
And the customer's record has no address
```

### Flow and detail without a UI (API)
The response is the module; the stock is stored state the response does not show. The rejection is one detail scenario, with no flow twin; its status and codes are quoted because the contract gives them.
```gherkin
@flow
Scenario: Cancelling an order that was not shipped releases its stock
  Given there is an order that was not shipped
  When I cancel the order
  Then the response says the order is cancelled
  And the stock of each of its products is what it was before the order

@detail
Scenario Outline: Cancelling an order <state> is rejected with its own error
  Given there is an order <state>
  When I cancel the order
  Then the response has status 409
  And the response has the error code "<code>"

  Examples:
    | state             | code            |
    | already shipped   | ORDER_SHIPPED   |
    | already cancelled | ORDER_CANCELLED |
```

### Counters → incremental states, one outline, related counters grouped
```gherkin
Scenario Outline: The import summary counts what happened: <case>
  Given the shop's catalogue is <starting state>
  And the supplier publishes <what it publishes>
  When the import job runs
  Then the summary says <added> added and <unchanged> already there
  And the summary says <skipped> skipped as discontinued

  Examples:
    | case                    | starting state             | what it publishes       | added | unchanged         | skipped |
    | first time              | empty, never imported      | products the shop lacks | all   | none              | none    |
    | again, no changes       | already imported           | the same products       | none  | all               | none    |
    | again, one more         | already imported           | the same and one more   | 1     | the previous ones | none    |
    | again, two more         | already imported           | the same and two more   | 2     | the previous ones | none    |
    | again, one discontinued | imported, one discontinued | the same products       | none  | the others        | 1       |
```

