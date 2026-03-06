# NewsCompanionKit -- Implementation Plan

## Overview

NewsCompanionKit is a reusable Swift Package that adds an AI-powered
companion layer to news articles.

When a user taps the AI icon on an article, the system generates:

-   A quick summary
-   Key bullet insights
-   Why the story matters
-   Conversational topics users can explore

The goal is to make long news articles faster to understand, easier to
scan, and more engaging to explore.

------------------------------------------------------------------------

# Architecture

The architecture is modular to keep the package clean, reusable, and
easy to extend.

NewsCompanionKit │ ├── ArticleFetcher │ ├── AIClient │ ├── GeminiClient
│ ├── ConversationEngine │ └── Models

Each module has a single responsibility and can evolve independently.

------------------------------------------------------------------------

# Package Name

Recommended name:

NewsCompanionKit

Alternative options:

-   ArticleCompanionKit
-   StoryCompanionKit
-   NewsInsightKit
-   ArticleAIKit

------------------------------------------------------------------------

# Modules

## ArticleFetcher

### Responsibility

Extract clean article content from a given URL.

### Input

URL

### Output

ArticleContent { title bodyText leadImageURL }

### Implementation Strategy

Extraction priority:

1.  Use the app's internal article API if the domain belongs to the news
    publisher.
2.  Fall back to HTML extraction using a Readability-style parser.
3.  Clean the output by removing:
    -   Ads
    -   Navigation content
    -   Author metadata
    -   Unrelated HTML sections

### Performance Optimization

Add caching:

Cache key:

articleURL

Use:

-   Memory cache
-   Disk cache

This prevents repeated extraction for the same article.

------------------------------------------------------------------------

## AIClient

AIClient abstracts the AI provider layer.

A protocol-based design allows swapping providers without changing the
core system.

### Protocol

``` swift
protocol AICompleting {
    func complete(prompt: String) async throws -> String
}
```

### Initial Implementation

GeminiClient

Future providers may include:

-   OpenAI
-   Claude
-   Local LLM models

------------------------------------------------------------------------

## ConversationEngine

This is the core intelligence module.

### Responsibility

Convert article content into structured insights that power the AI
companion UI.

### Input

ArticleContent

### Output

CompanionResult

### Responsibilities

-   Generate summary
-   Generate bullet points
-   Generate conversational topics
-   Generate fact-check hints

------------------------------------------------------------------------

# Data Models

## ArticleContent

``` swift
struct ArticleContent {
    let title: String
    let text: String
    let leadImageURL: URL?
}
```

## CompanionResult

``` swift
struct CompanionResult {
    let summary: Summary
    let topics: [TopicChip]
    let factChecks: [FactCheck]
}
```

## TopicChip

``` swift
struct TopicChip {
    let title: String
    let prompt: String
}
```

------------------------------------------------------------------------

# AI Output Contract

The AI must return strict JSON so the result can be parsed safely.

{ "summary": { "oneLiner": "...", "bullets": \["...", "...", "..."\],
"whyItMatters": "..." }, "topics": \[ { "title": "What happens next?",
"prompt": "Based on the article, what are the likely next steps?" }, {
"title": "Key players", "prompt": "Who are the main people or
organizations and what do they want?" } \], "factChecks": \[ { "claim":
"...", "whatToVerify": "..." } \] }

------------------------------------------------------------------------

# Bottom Sheet UX

When the user taps the AI icon on an article:

### Loading State

Show a skeleton loading UI.

Target generation time: 2 to 3 seconds

### Display Order

1.  One-line summary
2.  Bullet point summary (3 to 5 bullets)
3.  Why the story matters
4.  Conversation topic chips

Optional:

Ask your own question

### UX Principle

The experience must remain scannable and lightweight.

Avoid:

-   Long paragraphs
-   Dense blocks of text

Focus on:

-   short insights
-   clear structure
-   tappable interaction

------------------------------------------------------------------------

# Conversational Topic Templates

Default topics:

1.  What happened in 30 seconds
2.  Why it matters to me
3.  What happens next
4.  Key players and motivations
5.  Biggest uncertainties
6.  Arguments for vs against
7.  What changed today vs yesterday
8.  How this affects money, safety, daily life
9.  Timeline so far
10. What to watch for next 7 days

Only 5 to 6 topics should be shown at a time to avoid UI overload.

------------------------------------------------------------------------

# Execution Plan

## Package Scaffolding

Create the Swift Package:

NewsCompanionKit

Define base models:

-   ArticleContent
-   CompanionResult
-   TopicChip
-   Summary
-   FactCheck

Define core protocols:

ArticleFetching\
AICompleting

------------------------------------------------------------------------

## Article Extraction

Implement ArticleFetcher

Pipeline:

URL → Extract Article → Clean Text → Return ArticleContent

Support two modes:

-   Internal article API
-   HTML extraction fallback

Add caching:

-   Memory cache
-   Disk cache

Cache key: URL

------------------------------------------------------------------------

## AI Summarization Engine

Implement GeminiClient

Responsibilities:

-   Send prompt
-   Receive structured JSON
-   Return parsed model

Prompt rules:

-   Force JSON response
-   Limit token size
-   Maintain deterministic structure

Error handling:

1.  Attempt JSON parsing
2.  If parsing fails retry once with instruction:

Return valid JSON only.

------------------------------------------------------------------------

## Conversation Engine

Create ConversationEngine

Responsibilities:

-   Build prompt
-   Send to AI client
-   Parse structured result
-   Produce CompanionResult

Add safeguards:

-   Trim extremely long articles
-   Detect empty content
-   Return fallback result if generation fails

------------------------------------------------------------------------

## SwiftUI Integration

Flow:

Tap AI icon\
↓\
generate(url)\
↓\
ArticleFetcher\
↓\
ConversationEngine\
↓\
AIClient\
↓\
CompanionResult\
↓\
Bottom Sheet UI

Display:

-   Summary
-   Bullets
-   Why it matters
-   Topic chips

------------------------------------------------------------------------

## Guardrails and Reliability

Implement:

-   Article length trimming
-   Timeout handling
-   Sensitive content filtering
-   Extraction failure fallback

Fallback UI:

Unable to generate summary for this article.

------------------------------------------------------------------------

## Telemetry and Experimentation

Track:

-   time_to_summary
-   topic_chip_taps
-   ai_icon_clicks
-   summary_completion_rate

Experiment variants:

Variant A: Summary only\
Variant B: Summary + conversation topics

------------------------------------------------------------------------

# Final Goal

Deliver a reusable Swift package that enables AI-powered article
understanding with minimal integration effort.

Example integration:

``` swift
let result = try await NewsCompanionKit.generate(url:)
```

The result returns structured insights ready to render in the UI
companion sheet.
