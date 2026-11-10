# ShooLiveActivity — owner: lead

Dynamic Island showing only the running score (EX-03). Driven by Live Activity push from the backend (path C, #49):
the extension sends `POST /live`, the backend sends APNs `liveactivity` pushes (start / update / end), so it works with
Shoo closed. Contract: contracts/api.md "Live score (Dynamic Island)". The in-page pill (`pill.js`) stays the offline,
instant signal. Why not the extension or the app directly: docs/spikes/dynamic-island.md.

- The push payload decodes into `ScoreActivityAttributes` (`ios/ShooShared/`): its keys are a contract.
- Compact island follows Figma node 882:2533 (logo left, 20 pt mini ring right). Expanded, minimal and lock screen have no
  Figma frame yet.
