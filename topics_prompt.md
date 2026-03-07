# Topic Prompt Guide

## Goal
Generate 5 to 6 topic chips from a single news article.

Each topic must feel:
- grounded in the article
- distinct from the other topics
- useful as a follow-up conversation path
- short enough for a chip title

## Output Contract
Return topic items in this shape:

```json
{
  "title": "What happens next",
  "prompt": "Based only on the article, what are the most likely next developments to watch?"
}
```

## Hard Rules
- Generate exactly 5 or 6 topics.
- Every topic must be directly supported by the article.
- Do not invent people, motives, outcomes, or timelines not implied by the article.
- Each title must be 2 to 5 words.
- Each title must be distinct and scannable.
- Each prompt must be one sentence.
- Each prompt must clearly ask for analysis of that specific angle.
- Avoid generic prompts that could apply to any article.
- Avoid repeating the same angle with slightly different wording.

## Required Topic Quality
Good topics usually cover different analytical angles such as:
- what happened in 30 seconds
- what happens next
- key players
- biggest uncertainties
- why it matters to me
- arguments for vs against
- timeline so far
- what to watch next

Pick the best 5 or 6 angles for the article. Do not force all angles if the article does not support them.

## Invalid Topics
Reject topics that are:
- too generic: "Learn more", "Deep dive", "More context"
- duplicate angles: "Next steps" and "What happens next"
- not grounded in the article
- too long for a chip
- vague about the requested analysis

## Preferred Style
- Titles should look like product-ready chips.
- Prompts should sound like a helpful assistant continuing the conversation.
- Keep wording neutral and factual.
- Prefer concrete wording over abstract phrasing.

## Recommended Generation Prompt

```text
Generate exactly 5 to 6 topic chips for this article.

Each topic must use this shape:
{ "title": "Short chip title", "prompt": "One-sentence follow-up prompt" }

Rules:
- Base every topic only on the article.
- No generic or reusable filler topics.
- Titles: 2 to 5 words, concise, distinct, product-ready.
- Prompts: one sentence, specific to the article, and useful for follow-up analysis.
- Cover varied angles where supported by the article, such as what happened, what happens next, key players, uncertainties, timeline, or impact.
- Do not repeat the same angle with minor wording changes.
- If the article is narrow, choose fewer angles but still return 5 strong topics by varying perspective carefully.
```

## Current Bottlenecks In Existing Prompt
- It lists example angles but does not require uniqueness.
- It does not define what makes a bad topic.
- It does not constrain title length strongly enough.
- It does not force article-grounded prompts.
- It does not prevent generic filler topics.
