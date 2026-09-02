---
type: daily
created: <% tp.date.now("YYYY-MM-DD") %>
context: <% tp.system.suggester(["work", "private"], ["work", "private"], false, "Which machine/context is this day?") %>
tags: [daily]
---

# <% tp.date.now("YYYY-MM-DD, dddd") %>

## Focus
<!-- One or two things that matter today. -->

## Log
<!-- Timestamped notes as the day goes. -->

## Worked on
<!-- Links to projects/repos touched today. -->

## Captured
<!-- Quick thoughts, ideas, links to triage later. -->

## Tomorrow
<!-- What to start with next. -->
