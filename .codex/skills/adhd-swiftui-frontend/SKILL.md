---
name: adhd-swiftui-frontend
description: Use this project skill when designing, auditing, or refactoring FocusFlow SwiftUI/AppKit frontend screens for ADHD-friendly learning support. It guides calm visual design, semantic colors, accessibility, progress visibility, recoverable interactions, and mature macOS SwiftUI implementation.
---

# ADHD-Friendly SwiftUI Frontend Design

## Purpose

Use this skill when designing, auditing, or implementing FocusFlow frontend work. FocusFlow is a macOS learning assistant for students who benefit from ADHD-friendly task support. Frontend changes should reduce cognitive load, support focus, make progress visible, and keep interactions calm, predictable, and recoverable.

This skill guides design decisions and implementation habits. It does not prescribe exact page layouts.

## Design North Star

Build an app that feels calm, obvious, and recoverable. Users should quickly understand where they are, what changed, what to do next, and how to undo or continue after interruption.

## Core Principles

### Calm Visual System

- Prefer warm off-white or deep charcoal backgrounds over pure white or pure black.
- Use low-saturation, muted colors for large surfaces.
- Use stronger colors only for semantic purposes: primary action, focus indicator, success, warning, error, and progress.
- Keep one dominant action color per screen.
- Avoid neon colors, animated gradients, busy decorative backgrounds, and competing accent colors.

### Color Never Carries Meaning Alone

Every color-coded state must also include text, shape, icon, label, or position.

- Error: red + icon + plain-language message.
- Completed task: green + checkmark + "Completed".
- Current step: accent color + filled state + "Step 2 of 4".

### Predictable Components

- Same action means same visual treatment.
- Same status means same label and icon.
- Same navigation pattern means same location and behavior.
- Back, cancel, undo, and save behavior should be obvious.

### Reduced Cognitive Load

- Chunk long content into small, meaningful sections.
- Present one primary decision at a time.
- Avoid dense screens with many equal-weight controls.
- Prefer progressive disclosure: essentials first, details on demand.
- Use short labels and concrete verbs.

### Executive Function Support

- Show the current goal.
- Show the next step.
- Show progress in small increments.
- Provide reminders and transitions gently.
- Let users pause, resume, and recover without losing work.

### Personalization As Accessibility

Settings should support theme, Dynamic Type, Reduce Motion, information density, sound or haptic feedback, timer visibility, and reminder frequency when these are relevant to the screen being changed.

## Recommended Theme

Use semantic design tokens rather than raw colors in views. When adding or refactoring color usage, read `references/ADHD_ColorTokens.swift` for the Calm Focus token shape and keep view code intent-driven.

Important token roles:

| Role | Use |
| --- | --- |
| `bgBase` | Main app background |
| `surfaceCard` | Cards, sheets, grouped content |
| `surfaceSubtle` | Secondary sections and disabled zones |
| `textPrimary` | Main text |
| `textSecondary` | Supporting text and metadata |
| `borderSubtle` | Dividers and card borders |
| `actionPrimary` | Primary buttons and active controls |
| `focusRing` | Keyboard focus and active learning indicator |
| `success`, `warning`, `error` | Semantic feedback states |
| `chipReading`, `chipPractice`, `chipMemory`, `chipBreak` | Category chips |

## Component Guidance

### Buttons

- One primary action per screen or card region.
- Primary buttons use the semantic primary action color.
- Secondary actions are quieter: outline, text button, or lower emphasis.
- Destructive actions require confirmation when consequences are not easily reversible.
- Labels should use concrete verbs, such as "Start Focus Session", "Review Mistakes", or "Save Plan".

### Cards

- A card represents one learning object or one task group.
- Each card needs a clear title, status, and next action.
- Avoid multiple competing CTAs inside one card.
- Use strips and chips for category or status, not decoration.

### Progress Indicators

- Show progress as concrete steps, not vague percentages only.
- Prefer "2 of 5 tasks done" over "40%" when space allows.
- Celebrate gently; avoid loud confetti by default.
- The current step must be visually distinct and labeled.

### Feedback Banners

- Feedback should be immediate, calm, and specific.
- Prefer supportive copy such as "Saved. You can keep going."
- Errors should explain what happened and how to fix it.
- Do not use color alone for feedback.

### Navigation

- Keep navigation stable and conventional.
- Preserve user state when navigating away.
- Make back, cancel, and close behavior predictable.
- Use clear page titles and section headings.
- Avoid surprising modal stacks.

### Forms And Inputs

- Use visible labels, not placeholder-only labels.
- Break complex forms into steps.
- Show validation near the field in plain language.
- Allow undo or correction whenever possible.
- Use examples and helper text only when they reduce confusion.

### Timers And Focus Sessions

- Timers should be calm and optional, not visually dominant by default.
- Allow users to hide, pause, extend, or reduce timer pressure.
- Use gentle state changes for transitions.
- Provide "resume where I left off" behavior.

### Motion

- Use animation only to clarify continuity or feedback.
- Respect Reduce Motion.
- Avoid autoplaying animations, pulsing elements, shaking errors, looping decorative motion, and sudden screen changes.
- Prefer opacity and position transitions over intense scale, bounce, or rotation.

## SwiftUI Implementation Habits

- Use semantic tokens such as `AppColor.actionPrimary`, not scattered hex values.
- Respect `colorScheme`, `dynamicTypeSize`, `accessibilityReduceMotion`, `accessibilityDifferentiateWithoutColor`, and `accessibilityContrast`.
- Prefer reusable components with intent-driven parameters: title, subtitle, icon, semantic state, action, loading state, disabled state, and accessibility labels.
- Model visible state explicitly with semantic enums instead of view-local booleans when behavior is shared.
- Icon-only buttons need meaningful labels and hints.
- Progress must be readable by VoiceOver, for example "2 of 5 tasks completed".
- Color-coded chips must include text labels.

## Definition Of Done

- Text contrast meets WCAG AA: 4.5:1 for normal text and 3:1 for large text.
- Focus states have visible affordances.
- No important meaning is communicated by color alone.
- Each screen or component region has one obvious primary next action.
- Long tasks are chunked and progress is visible.
- Dynamic Type does not break the UI.
- Reduce Motion is respected.
- Error states are calm, specific, and recoverable.
- VoiceOver labels make sense.
- Reusable components avoid copied layout logic.

