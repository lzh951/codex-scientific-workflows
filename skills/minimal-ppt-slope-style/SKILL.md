---
name: minimal-ppt-slope-style
description: Create or revise PowerPoint slides with key figures, concise natural text, and minimal decoration.
metadata:
  short-description: Minimal, content-first PowerPoint slides
---

# Minimal, content-first PPT

Use this skill when creating or revising a PowerPoint, especially a scientific or technical deck, where the user wants fewer decorative elements, no redundant subheadings, and natural wording with little AI residue. Treat a user-provided Slope reference as a cue for restrained, human-sounding writing rather than as content to copy.

## Core rule

Build each slide from the user's key figure or evidence and one concise message. Give every other object a job: identification, legibility, navigation, provenance, or an explicit user request. Omit objects without a job.

## Visual decisions

- Make the data-bearing figure the largest and most readable object on the slide.
- Use one slide title only when it helps identify the claim. Keep the title direct and specific.
- Keep subtitles, section bars, cards, badges, category tags, callout boxes, quote blocks, decorative rules, shadows, icons, dots, oversized page numbers, and repeated footers out of the default layout.
- Do not add small headings such as “热响应”, “XRD”, “统计”, or “结论” as summary labels unless they disambiguate independent panels or the user requests them. Keep labels that already belong to the source figure.
- Do not repeat chart axes, legends, or labels in a second text strip.
- Leave unused space empty. Do not fill it with explanatory copy.
- Add a source or provenance line only when the workflow requires it. Keep it unobtrusive and do not turn it into a decorative footer.
- Use native PowerPoint text boxes, connectors, and shapes only when they clarify the evidence. Preserve data-bearing source figures and editable objects such as Origin OLE; do not rasterize them to simplify the layout.

## Text decisions

Write in the restrained, natural style the user calls “Slope”: concrete wording, short sentences, active voice, and a clear link between evidence and claim.

- Name the observation and its implication. Prefer “降温时 R 相相关峰增强，升温路径回到单一峰。” over “综合热响应、XRD 与统计结果可知……”.
- Use a short phrase or one or two sentences. Put the result on the slide; leave narration to speaker notes.
- Cut filler such as “本页展示”, “下面将”, “可以看出”, “值得注意的是”, “进一步说明”, “综上所述”, and generic marketing language.
- Avoid rhetorical setups, slogan-like conclusions, stacked negations, vague claims, and mechanical three-part summaries.
- Preserve evidence strength. “提示”, “支持”, and “与……一致” must remain distinct from “证明” or “导致”. Do not invent values, mechanisms, or headings from filenames.
- Use the shortest wording that still identifies the sample, condition, comparison, or uncertainty needed to read the figure.

## Working sequence

1. Identify the key figure, the one slide claim, and any labels already embedded in the source artwork.
2. Draft the smallest layout that makes the figure and claim readable.
3. Remove every redundant label, panel summary, decorative object, and explanatory sentence.
4. Check the wording for directness, concrete evidence, active voice, and bounded scientific claims.
5. After every PPT edit, reopen the actual output deck and render it at its final slide size. Inspect the full slide and tight crops for figure legibility, text size, overflow, overlap, accidental leftovers, and unwanted extra elements. Check that embedded or editable data objects remain present when the source requires them.
6. Open a newly created PPT for the user after the visual check.

## Acceptance check

The slide passes when the key figure is easy to read, the text states the needed claim in plain language, the source evidence remains intact, and no unrequested decoration, subtitle, small heading, summary strip, or duplicated label competes with the evidence. Report visual checks separately from scientific validation.
