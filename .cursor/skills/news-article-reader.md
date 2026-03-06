---
name: news-article-reader
description: >
  Fetch, parse, and extract clean readable text content from news article URLs. Use this skill
  whenever a user provides a URL (or list of URLs) and wants to: read an article, summarize it,
  compare articles, extract quotes, analyze coverage, or do any task that requires getting the
  actual text content out of a news page. Trigger even if the user doesn't say "article" — any
  web URL where readable content extraction would help (e.g. "check this link", "what does this
  say", "iterate through these URLs", "pull text from these pages") should use this skill.
  Especially useful for iterating over multiple URLs to build summaries, comparisons, or digests.
---

# News Article Reader Skill

This skill enables Claude to fetch news article URLs, extract clean body text (stripping ads,
nav bars, sidebars, scripts, and boilerplate), and present readable content for further analysis.

---

## When to Use This Skill

- User shares one or more URLs and wants to read/summarize/compare them
- User says "iterate through these links", "get the text from these articles", etc.
- User wants a news digest, coverage comparison, or quote extraction from web pages
- Any task requiring the actual article body text (not just headlines/metadata)

---

## Step-by-Step Workflow

### 1. Identify URLs

Extract all URLs from the user's message. If none are provided but the user implies fetching
content (e.g., "here are the links: ..."), ask them to share the URLs.

### 2. Fetch Each URL

Use the `web_fetch` tool on each URL. For each fetch:
- Set `text_content_token_limit` to `4000` for standard articles (raise to `8000` for long-form)
- Handle errors gracefully — if a fetch fails, note it and continue with the rest

```
web_fetch(url=<article_url>, text_content_token_limit=4000)
```

### 3. Extract Clean Text

The raw web_fetch output includes HTML artifacts. Apply these extraction rules:

**Keep:**
- Article headline / h1
- Byline and publication date (if present)
- Article body paragraphs
- Pull quotes and blockquotes

**Discard (do not include in output):**
- Navigation menus, headers, footers
- Ad copy and promotional text
- "Related articles" / "You might also like" sections
- Cookie notices, subscription prompts
- Social share button labels
- Script/style tag content
- Repetitive site boilerplate (site name repeated many times, etc.)

**Heuristic**: Focus on the longest continuous block of coherent prose — that's almost always
the article body.

### 4. Present the Content

For **a single article**, present:
```
## [Article Title]
*Source: [domain] | [Date if available]*

[Clean article body text]
```

For **multiple articles** (iteration mode), present each as a numbered section:
```
---
### Article 1: [Title]
*Source: [domain] | [Date]*
[Body text or summary]

---
### Article 2: [Title]
...
```

If the user asked for **summaries** rather than full text, summarize each article in 3–5
sentences after extracting the body — do NOT just copy the meta description or lede.

---

## Iteration Mode (Multiple URLs)

When given a list of URLs, process them sequentially using `web_fetch`. For large batches
(5+ URLs), inform the user you're processing them and provide a progress update.

**Template for iteration:**
1. Announce: "Fetching [N] articles..."
2. Fetch URL 1 → extract → store result
3. Fetch URL 2 → extract → store result
4. ... (continue for all URLs)
5. Present all results in a clean numbered format

If the user wants a **digest or comparison**, after extracting all articles:
- Identify common themes across articles
- Note differences in coverage, framing, or emphasis
- Present a unified synthesis followed by per-article breakdowns

---

## Error Handling

| Situation | Action |
|-----------|--------|
| Fetch returns 403/paywalled | Note "Paywall detected — only preview text available" and extract what's visible |
| Fetch returns 404 | Note "Article not found (404)" and skip |
| Fetch returns empty/garbled content | Note "Could not extract readable content" and skip |
| URL is not a news article (e.g. homepage) | Note the issue, extract what text is available |

Never silently skip a URL — always report its status to the user.

---

## Output Quality Checklist

Before presenting output, verify:
- [ ] No nav/menu text leaking into article body
- [ ] No repeated site name boilerplate
- [ ] Headline is present and accurate
- [ ] Body text reads as coherent prose
- [ ] Source attribution (domain + date) is included
- [ ] Errors/skipped URLs are clearly noted

---

## Examples

**Single article summary:**
> User: "Summarize this: https://news.sky.com/story/four-arrested-on-suspicion-of-syping-for-iran-13515093"
> → Fetch → Extract body → Write 4-sentence summary with headline + source

**Iteration / digest:**
> User: "Get the text from all these links and compare how they cover the Fed rate decision:
> [url1] [url2] [url3]"
> → Fetch all 3 → Extract bodies → Present per-article text → Add comparative analysis

**Paywall case:**
> User: "Read this NYT article for me: [url]"
> → Fetch → Detect paywall → Return: "Only the preview is accessible (paywall). Here's what's
> available: [lede paragraph]"