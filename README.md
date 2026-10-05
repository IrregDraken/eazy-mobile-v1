# Eazy Mobile V1

Eazy Mobile V1 is the fresh Flutter rebuild of Eazy.

## Non-negotiable visual rule

This repository uses **zero visual assets from the old Eazy Flutter app or Eazy Mobile V2**.

The current visual system is rendered from Flutter primitives, custom geometry, typography, iconography, gradients and layout. If Eazy V1 eventually needs illustrations or imagery, they will be created specifically for V1.

## What is being combined

### From the original Flutter Eazy
- proven product workflows
- social-first navigation
- marketplace, cart and order flows
- wallet and transaction concepts
- chat and conversation flows
- profile, settings and support flows
- endpoint contracts and hard-earned edge cases

### From Eazy V2
- the newer Railway backend target
- current provider boundaries
- current Firebase identity architecture
- newer product direction
- stronger error handling expectations

### Rebuilt for V1
- Flutter-only implementation
- modular feature architecture
- fresh visual language
- typed networking boundary
- secure session storage
- explicit loading, empty and error states
- no demo data as a production fallback

## Current foundation

The first implementation commit establishes:
- Material 3 dark product system
- fresh welcome/auth experience
- Firebase email authentication boundary
- V2 Railway API client
- secure access-token storage
- social feed shell
- marketplace shell
- wallet shell
- chat shell
- profile shell
- navigation
- CI for analyze/test

Native Android/iOS project generation and provider-specific credentials are intentionally kept separate from the product source until the core architecture is settled.

See docs/ARCHITECTURE.md and docs/MIGRATION_MATRIX.md for the rules governing the rebuild.
