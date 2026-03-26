# Rule: Telegram And Other User-Facing Messaging Channels Must Not Leak Internal Activity

For Telegram and other user-facing messaging channels:

1. Do not emit internal execution telemetry as user-visible replies.
   Forbidden examples:
   - `Activity log`
   - `Running: ...`
   - `Searching memory...`
   - `thinking...`
   - raw tool names
   - raw shell commands
2. Allow at most one short human-facing progress preface before the final answer.
   Good examples:
   - `Сейчас проверю память и каталог навыков.`
   - `Посмотрю на сервере и вернусь с результатом.`
3. Tool and runtime failures must be summarized in normal user language.
   Do not forward raw activity dumps, traces, or tool-event streams into the chat.
4. Authoritative Telegram UAT must fail closed on both:
   - a reply that looks like internal telemetry
   - a recent invalid incoming activity leak already present in the quiet window before the new probe send
5. If such leakage is observed live, treat it as a user-facing reliability incident.
   Reconcile or reset the contaminated Telegram session/chat before trusting any new authoritative run.

Why:

- user-facing chats are not debug panes
- internal telemetry degrades UX and leaks implementation details
- quiet chat attribution is unsafe if the last incoming message is already an invalid telemetry dump
