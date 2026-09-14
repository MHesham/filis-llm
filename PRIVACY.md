# Privacy

This page describes what this chat service does and does not guarantee about your
conversations. It's intentionally high-level — for the full technical audit behind
these statements, contact the operator.

## What we guarantee

- Your prompts and responses run entirely on infrastructure we control. Nothing is
  sent to a third-party AI provider (OpenAI, Anthropic, or similar).
- Conversations are never used to train any model outside this deployment.
- New accounts require operator approval before they can chat.
- Your chats are not shared with other users, and chat sharing to the public
  Open WebUI community site is disabled.
- We don't sell or share your data with third parties.

## What we don't guarantee

- **The operator can technically access stored chat data.** The database is not
  encrypted at rest, so anyone with legitimate server access could in principle
  read it directly, independent of any in-app privacy setting. Please don't share
  anything here you wouldn't want a system administrator to be able to see.
- We don't currently guarantee a fixed data-retention or deletion timeline — chat
  history persists until an operator removes it.
- Standard internet infrastructure (our hosting provider and CDN) terminates TLS
  as part of normal operation, meaning that infrastructure — not just us — briefly
  handles decrypted traffic in transit, the same as for any HTTPS site.

## Questions

Reach out to **chatsupport@filis.dev**.

---
*Last updated 2026-09-14.*
