# peachq-starter

Run your q project's tests in GitHub Actions on [peachq](https://github.com/peachq-org/peachq), an open-source (MIT)
q that any runner may download. Click **Use this template**, or copy the workflow below.

```yaml
# .github/workflows/peachq.yml
steps:
  - uses: actions/checkout@<sha>
    with: {persist-credentials: false}
  - uses: peachq-org/setup-peachq@v1.0.0
    with:
      version: 0.92.20261116
  - run: $QCMD tests/run.q -classic
  - if: always()
    uses: actions/upload-artifact@<sha>
    with: {name: peachq-junit, path: junit.xml}
```

This repo is that workflow plus one small project:

- `src/math.q` holds the code.
- `tests/mathTest.q` holds the [qunit](tests/qunit.q) tests.
- `tests/run.q` runs them, writes `junit.xml`, and exits 1 if any test fails.

`-classic` gives kdb+'s display and error text, so tests written against kdb+ output compare like for like. Each
engine's arguments go after the script: `q [file] [-options]`. The workflow runs on Linux; add `macos-latest` if you
ship on Mac. To install peachq without a third-party action, see
[setup-peachq](https://github.com/peachq-org/setup-peachq#without-the-action-download-from-peachqorg).

## Just check it loads

Have no tests yet? Put this in `tests/load.q`, and run `$QCMD tests/load.q -classic`:

```q
@[system; "l src/math.q"; {-2 "load failed: ",x; exit 1}];
-1 "loaded";
exit 0;
```

## Use your own test runner

Replace the `run:` line with your runner's command, for example `$QCMD tests/all.q -classic`. Its exit code is the
verdict. Upload whatever JUnit XML it writes as `peachq-junit`.

## Known gaps

`peachq-known-gaps.txt` lists tests known to fail on peachq, one per line: `.mathTest.testName  # why`. On peachq,
`tests/run.q` fails on any unlisted failure, and also on a listed test that now passes, so the list only shrinks.

Think a failure is a peachq bug? Raise an issue: https://github.com/peachq-org/peachq/issues/new?template=compat.yml

## Licence

MIT, see [LICENSE](LICENSE). `tests/qunit.q` is © TimeStored, MIT (SPDX header in the file).
