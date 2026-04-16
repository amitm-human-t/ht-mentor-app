# Release + TestFlight Acceptance Checklist (iPad v1)

## Purpose
Define concrete exit criteria before wider trainer rollout.

## 1) Functional parity gates
- [ ] All five v1 tasks launch and complete runs
- [ ] Supported modes behave as specified per task
- [ ] Trainer controls (start/pause/reset/exit + task actions) work consistently
- [ ] Overlays/HUD render correctly and can be toggled
- [ ] User flows (create/select/edit user) are functional

## 2) Device and performance gates
- [ ] Passed on iPad Pro M1
- [ ] Passed on iPad Pro M2
- [ ] Passed on iPad Pro M4
- [ ] No sustained sub-30 FPS behavior in standard scenarios
- [ ] No critical thermal instability during 10+ minute runs

## 3) BLE and Locked Sprint gates
- [ ] HandX pairing/discovery stable
- [ ] Locked Sprint gating works (disabled when no HandX)
- [ ] Mid-run disconnect policy works: pause + 10s grace + auto-end on timeout
- [ ] Reconnect within grace resumes run correctly

## 4) Data/privacy gates
- [ ] No video recording artifacts stored in v1
- [ ] Raw session telemetry not retained long-term
- [ ] Summary-level run/user/leaderboard data persists correctly
- [ ] User data deletion flow works end-to-end

## 5) Permissions and recovery gates
- [ ] Camera permission denial flow is clear and recoverable
- [ ] Bluetooth permission denial flow is clear and recoverable
- [ ] Missing model asset failure shows recoverable UX
- [ ] Failure messages include clear next action

## 6) TestFlight readiness
- [ ] Build metadata and release notes prepared
- [ ] Known limitations documented
- [ ] Pilot tester group defined (trainers + internal QA)
- [ ] Feedback capture workflow agreed

## 7) Go/No-Go signoff
- [ ] Product signoff
- [ ] Engineering signoff
- [ ] Clinical/trainer usability signoff
