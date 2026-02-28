---
description: Launch expert consilium for discuss a question in parallel, Each expert works independently in isolated worktree
argument-hint: "[question]"
---

# Consilium Skill
Launch expert consilium for panel discussion of problem

## Instructions
1. **Receive the Question**
   - Parse the question from user input
   - Identify key aspects (technical, architectural, operational, strategic)

2. **Launch 19 Expert Agents in Parallel**
   - Spawn all 19 expert agents using Task tool
   - Each agent works in isolated worktree (`isolation: worktree`)
   - Each agent works in background (`background: true`)
   - Agents run independently and not sequentially

3. **Wait for All Opinions**
   - Monitor completion of all agents
   - Collect results
   - Handle timeouts gracefully

4. **Coordinate Discussion**
   - Use SendMessage to enable expert communication
   - Experts can send messages to each other
   - Facilitate cross-expert discussion
   - Architect (Team Lead) moderates discussion

   - Synthesize opinions
   - Identify agreements
   - Highlight conflicts
   - Build consensus

5. **Generate Final Report**
   - Compile all expert opinions
   - Create summary of consensus
   - Provide final recommendation
   - Include confidence level

## Expert Agent Types
Use `subagent_type: "general-purpose"` for all experts

## Communication Protocol
Experts use SendMessage tool:
- Send messages to other experts
- Respond to messages from other experts
- Architect coordinates discussion
- Tag relevant experts in messages content

- Use short, focused messages
- Keep discussion productive

## Output Format
```markdown
# Consilium Report

## Question
[The question being discussed]

## Expert Opinions

### Architect (Team Lead)
- Opinion: [Summary]
- Status: Lead

### [Expert Name]
- **Key Points:**
  - [Point 1]
  - [Point 2]
  - [Point 3]
- **Opinion:** [Summary]
- **Status:** ✅ Agreed / ⚠️ Disagreed / ❌ Blocked

[... repeat for all 19 experts opinions]

## Consensus
- **Agreed Points:** [List]
- **Disagreements:** [List]
- **Resolution:** [How conflicts were resolved]

## Final Recommendation
[Unified recommendation]

## Confidence Level
- High / Medium / Low
- **Consensus Strength:** Unanimous / Strong / Weak

## Next Steps
1. [Next step 1]
2. [Next step 2]
3. [Next step 3]
