# peachq-starter

Run your q project's checks in GitHub Actions on [peachq](https://github.com/peachq-org/peachq), and optionally
alongside other q engines.

peachq is an open-source (MIT) q. Because anyone may download and run it, a GitHub-hosted runner can run q code on
every push and pull request. This template gives you:

- `qci.sh`, a check runner. It needs only bash, and python3 only if you want per-test results from JUnit XML.
- `.github/workflows/peachq.yml`, the "runs on peachq" workflow. It installs a pinned peachq with
  [setup-peachq](https://github.com/peachq-org/setup-peachq) and runs your checks.
- `.github/workflows/engines.yml`, which runs the same checks on every q engine a runner has and tabulates the
  results side by side.
- Three examples in `examples/`, one for each way of checking a project.

## Quick start

1. Click **Use this template**, or copy `qci.sh`, `qci-known-gaps.txt` and `.github/workflows/` into your project.
2. Describe your project in a `.qci` file at its root:

   ```sh
   QCI_ENTRY=lib:init.q
   QCI_TESTS=$QCMD tests/run.q
   QCI_JUNIT=qci-junit.xml
   QCI_TIMEOUT=300
   ```

   - `QCI_ENTRY` is what to load: a `file`, or `dir:file` to `\l` it from `dir`. Separate several with commas.
   - `QCI_TESTS` (optional) is any shell command. `$QCMD` in it is the q being checked.
   - `QCI_JUNIT` (optional) is the JUnit XML your tests write, for per-test results.
   - `QCI_TIMEOUT` (optional) is the limit in seconds for each load and for the tests. The default is 300.

   Each line is `KEY=VALUE` with no quotes and no trailing comments. A line starting with `#` is a comment.

3. In `.github/workflows/peachq.yml`, replace the `project:` list with `.`.
4. Run it locally: `PEACHQ_Q=/path/to/peachq/q ./qci.sh`.

Values in the environment override `.qci`. `$QCMD` in `QCI_TESTS` stays literal in the file and is expanded when the
tests run.

## The three levels

| level | configured by | a check passes when | example |
|---|---|---|---|
| **Loads** | `QCI_ENTRY` | each entry loads in a fresh q, with no error and within the timeout | [`examples/loads-only`](examples/loads-only) |
| **Tests** | `QCI_TESTS` | the command exits 0 | [`examples/own-tests`](examples/own-tests) |
| **Per test** | `QCI_JUNIT` | each `<testcase>` in the report passes or is skipped | [`examples/qunit`](examples/qunit) |

A load runs `@[system;"l <file>";{-1 "qci-load-error: ",x; exit 3}]` from the entry's directory, so the first error
is reported. The qunit example uses the [qunit](examples/qunit/qunit.q) test framework, unchanged, and writes JUnit
XML from `.qunit.runTests`' result table.

Results are written to `qci-results/`: `<engine>.csv` (`check,status,message`), `<engine>.id` (the engine's
identity: `.z.K`, `.z.k`, `.z.v` where defined, and its arguments) and each run's logs. Status is one of `pass`,
`fail`, `error`, `timeout` or `skip`.

## Engines

`qci.sh` checks one or more q engines. Each engine has a slot, filled by an environment variable that names its
binary:

| slot | variable | if the variable is unset |
|---|---|---|
| `peachq` | `PEACHQ_Q` (set by setup-peachq) | `QCMD`, then `q` on `PATH`, then the QHOME locations below, whichever is peachq |
| `kx` | `KX_Q` | `$QHOME/<arch>/q`, then `~/q/<arch>/q`, where `<arch>` is this machine's `l64`, `l64arm`, `m64` or `w64` |
| `korze` | `KORZE_Q` | nothing |
| `l` | `L_Q` | nothing |

`QCMD` alone is "the q to run". A binary is trusted as labelled when a variable names it. A binary found by searching
is first asked whether it is peachq (does `.pq.version` exist). If it is, it can fill only the peachq slot. Any
other q found on QHOME is labelled "q on QHOME", and any on `PATH` "q on PATH" (engine `path`).

```sh
./qci.sh           # every engine whose variable is set; just peachq when none is
./qci.sh kx        # one engine (named or found)
./qci.sh all       # every engine that can be found
./qci.sh compare   # the table of the last run's engines, below
```

Engines run in alphabetical order. peachq has a special place in three ways only: it is the default when nothing is
set, it is the only engine the workflows install, and it is the only engine the report links go to.

**`-classic` by default.** peachq runs as `q <file> … -classic`, which gives kdb+'s console display and error text,
so tests written against kdb+ output compare like for like. Set `PEACHQ_ARGS` to change it (`PEACHQ_ARGS=` runs
peachq's modern mode). `KX_ARGS`, `KORZE_ARGS` and `L_ARGS` add arguments for the other engines. An engine's
arguments always come after the script, as in `q [file] [-options]`.

**The KX slot is supported but not verified by peachq. We never run kdb+.** It works with any q binary you are
licensed to run.

## Comparing engines

`qci.sh compare` turns `qci-results/` into a markdown table of checks against engines, with each engine's identity.
It prints the table and adds it to the job summary (`$GITHUB_STEP_SUMMARY`). To compare, run several engines in one
run: `./qci.sh all`, or name them, as in `./qci.sh kx peachq`.

`engines.yml` (run it from the Actions tab) does this in CI. It installs only peachq. Every other engine is yours to
provide:

- On a **self-hosted runner**, a q in the runner's `QHOME` is found by itself. Otherwise set `KX_Q`, `KORZE_Q` or
  `L_Q` in the runner's environment, or as repository variables. Set the repository variable `QCI_RUNNER` to the
  runner's label.
- On a **hosted runner**, add your own install step before `qci`, for an engine whose licence allows it.

## Known gaps

`qci-known-gaps.txt` lists checks known to fail on peachq:

```text
load:lib:init.q  # peachq-lacks: -19! (compressed writes), which init.q calls at load
test:.mathTest.testBig  # tree-bug: #12, the test relies on a dictionary's order
```

An unlisted failure fails the run, and so does a listed check that now passes. The list can only shrink. When JUnit
results are present, a failing `tests` row is explained by the failing per-test rows. A timeout, a crash or an
unreadable report always fails. For any other engine, the same holds with `qci-known-gaps-<engine>.txt`.

## Reporting differences to peachq

Where peachq's result differs from another engine's, `qci.sh compare` adds a **report to peachq** link. It opens a
[prefilled issue](https://github.com/peachq-org/peachq/issues/new?template=compat.yml) holding the check's name, each
engine's status and message, and each engine's version. It never includes your source code. Paths are shortened to
`.` and `~`. Nothing is sent until you review the issue and submit it yourself. qci never files issues. A difference
between two other engines gets no link.

## Installing peachq without a third-party action

If your organisation allows only approved actions, install with setup-peachq's `install.sh`. You can fetch it from a
pinned commit and check its sha256, or copy it into your repository:

```yaml
- run: |
    q=$(bash install.sh --version 0.92.20261115 --dir "$RUNNER_TEMP/peachq")
    echo "PEACHQ_Q=$q" >> "$GITHUB_ENV"
```

It verifies each download's checksum and can use your own artifact store (`PEACHQ_DIST_URL`). See the
[setup-peachq README](https://github.com/peachq-org/setup-peachq#without-the-action).

## Badge

```markdown
[![runs on peachq](https://img.shields.io/github/actions/workflow/status/OWNER/REPO/peachq.yml?label=runs%20on%20peachq&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxNiAxNiI%2BPGNpcmNsZSBjeD0iOCIgY3k9IjkuNSIgcj0iNiIgZmlsbD0iI2ZmYjM4YSIvPjxwYXRoIGQ9Ik04IDMuNVE5IDEgMTIgMS41UTExIDQgOCAzLjVaIiBmaWxsPSIjMmM4YjU3Ii8%2BPC9zdmc%2B&color=f28b57)](https://github.com/OWNER/REPO/actions/workflows/peachq.yml)
```

Replace `OWNER/REPO` (twice) with your repository. shields.io can read only public repositories. For a private one,
use GitHub's own badge:

```markdown
[![runs on peachq](https://github.com/OWNER/REPO/actions/workflows/peachq.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/peachq.yml)
```

## Licence

MIT, see [LICENSE](LICENSE). `examples/qunit/qunit.q` is © TimeStored, MIT (SPDX header in the file).
