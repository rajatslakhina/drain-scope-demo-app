# DrainScope Demo

**A checkout that gets cancelled 400 ms in — and a teardown that runs anyway.**

This is the companion app for
[**drain-scope-kit**](https://github.com/rajatslakhina/drain-scope-kit): a small
iOS app you can run in the Simulator to watch the failure mode the library
exists to remove, and then watch it not happen.

The app acquires five resources during a simulated checkout, each registering
its own teardown step. Then it cancels the operation mid-flight. Spawned as
ordinary child tasks, that cleanup would inherit the cancelled context and
silently do nothing. Here it runs on a shielded, budgeted island, and every step
lands in a transcript you can read on screen.

## Why this matters

Under cancellation, missing cleanup does not throw, does not log, and does not
reproduce in a normal test run. The bug is *silence*. The only way to know
whether your rollback ran is to make the teardown produce evidence — which is
what the transcript in this app is.

The policy presets are the point of the demo. The same five steps produce
genuinely different outcomes depending on the budget, and each preset is a
decision a lead has to make deliberately rather than discover in a crash log:

| Preset | Budget / grace | What you see |
|--------|----------------|--------------|
| **Tight** | 250 ms / 200 ms | Wishlist throws (`failed`), analytics overruns its cap (`timedOut`), the budget is then gone so inventory is dropped (`skipped`) — and both required steps still get their grace and `complete`. Four of the five outcome kinds in one transcript. |
| **Default** | 2 s / 250 ms | Everything is reached and given all the time it needs. The wishlist sync still fails: a budget cannot fix a broken step. |
| **Hostile** | 0 s / 100 ms | Every best-effort step is dropped on sight; only required work runs. The termination posture. |
| **Patient** | 30 s / 5 s | Batch and CLI shape, where finishing beats exiting. |
| **Doomed** | 0 s / 0 s | Nothing is granted any time. The required steps read `notAttempted`, not `timedOut` — they never started, and the transcript says so rather than claiming they were cancelled mid-flight. Badge flips to **INCOMPLETE**. |

`Tight` is selected on launch because it is the most informative. Running the
real executor against exactly these five steps under exactly this policy produces:

```
0. sync-wishlist        [bestEffort] → failed    (23ms)
1. flush-analytics      [bestEffort] → timedOut  (232ms)
2. rollback-transaction [required]   → completed (63ms)
3. release-payment-hold [required]   → completed (82ms)
4. reserve-inventory    [bestEffort] → skipped   (0ms)
elapsed=401ms  budgetExhausted=true  requiredWorkCompleted=true
```

Four of the five outcome kinds, and the badge still reads **REQUIRED WORK DONE** —
which is the design working, not failing. Two best-effort steps were lost and
that is exactly what declaring them best-effort was for.

(That transcript is measured, not imagined: it comes from running a scratch
consumer package that replicates `DemoScenario.steps` against the published
executor on Linux. The rendering is what has not been seen — see below.)

## Screenshots

**There are none, and that is deliberate rather than an oversight.**

This app was built by an unattended scheduled run, which cannot obtain
computer-use approval on this machine. Permission to drive Xcode and the
Simulator was requested three times (twice for Xcode + Simulator, once narrowed
to the Simulator alone) and refused each time with:

> Computer-use access to "Simulator" can't be approved during a scheduled run.
> To grant it, send a message in this conversation (the approval card will
> appear), or add the app to the scheduled task's settings. (Retrying returns
> this same result.)

So no screenshot was captured, and none is mocked up or described here.

Be careful with the distinction, because it is easy to blur and this README will
not blur it: **this app has not been launched on a Simulator, and at the time this
was written it had not been compiled either.** The CI job below compiles it for an
iOS Simulator, which is a weaker claim than running it — and a claim that only
becomes true once that job has actually reported. See **Verification**.

## Running it

```bash
git clone https://github.com/rajatslakhina/drain-scope-demo-app.git
cd drain-scope-demo-app
open Demo.xcodeproj
```

Then in Xcode: select the **Demo** scheme, pick any iOS Simulator, and press
Run (⌘R). Xcode resolves `drain-scope-kit` from GitHub on first open — it is a
remote package reference, not a local path, so nothing needs to be checked out
side by side.

Press **Run, then cancel mid-flight** to see the headline case.

## Dependency

```
https://github.com/rajatslakhina/drain-scope-kit.git
kind = upToNextMajorVersion, minimumVersion = 1.0.0
```

A **version range** (`>= 1.0.0, < 2.0.0`) against released tags — not a branch.
Being precise about what that does and does not buy: a clone made a year from now
resolves the newest published `1.x`, not necessarily the exact tree this README
describes. It does guarantee no breaking-change drift and no "whatever `main`
happened to be that day", which is the failure mode `branch = main` has. If you
want byte-identical resolution, commit a `Package.resolved` or switch the
requirement to `exactVersion`.

## Verification

### What has and has not been established

- **Not launched.** No Simulator was ever booted. No screenshot exists.
- **Not compiled at the time of writing.** The CI job below is the first thing
  that will ever compile `Demo/DemoApp.swift` and `Demo/CheckoutView.swift`; the
  environment that produced them had no macOS toolchain and no iOS SDK. Its
  result will be linked under **Continuous integration** below; read that, not this
  sentence, for whether the app builds.
- **What *was* checked without a compiler:** both Swift files parse cleanly
  (`swiftc -parse`). The hand-written `project.pbxproj` was validated
  programmatically — braces and parens balanced, and all 24 object IDs confirmed
  both defined and referenced with zero dangling references. The shared scheme was
  validated as well-formed XML with a `BlueprintIdentifier` matching the real
  target.
- **The library underneath is properly tested and genuinely run**: 47 XCTest
  cases, 0 failures, Swift 6.0.3 on Linux, including a negative control that
  asserts the naive pattern fails. The Tight-policy transcript quoted above was
  produced by executing the real code. See the
  [library repo](https://github.com/rajatslakhina/drain-scope-kit).

### Continuous integration

[![CI](https://github.com/rajatslakhina/drain-scope-demo-app/actions/workflows/ci.yml/badge.svg)](https://github.com/rajatslakhina/drain-scope-demo-app/actions/workflows/ci.yml)

One job on every push, on `macos-15` — the
[Actions tab](https://github.com/rajatslakhina/drain-scope-demo-app/actions) is the
live answer:

1. `xcodebuild -resolvePackageDependencies` — proves `drain-scope-kit` genuinely
   resolves from GitHub at the version this project asks for, rather than from
   anything vendored or cached in this repo.
2. `xcodebuild build -scheme Demo -destination 'generic/platform=iOS Simulator'` —
   compiles the app against it.

`generic/platform=iOS Simulator` rather than a named device is deliberate. Pinning
to `name=iPhone 16,OS=latest` ties the job to whichever simulator *runtimes* happen
to be installed on that day's runner image, and they are not guaranteed; a
compile-only check needs no device to exist.

**Both steps passed on the commit that completed this repo's initial push.** Be
precise about what that establishes: the remote package resolves, and this app
compiles for an iOS Simulator. It does not establish that the app launches,
renders, or survives a tap — no Simulator was booted by that job or by anything
else. That gap is the one described under **Screenshots** above, and it is the only
thing standing between this repo and a complete verification story.

## License

MIT. See [LICENSE](LICENSE).
