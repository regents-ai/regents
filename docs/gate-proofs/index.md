# Gate release proofs

The transcripts were run from pre-amend candidate commit
`38c5f8a2d319b317c2eab09de6e752346c1b1238`. Each transcript prints that
checkout and `git rev-parse HEAD`, followed by the tested `bin/gate.sh` blob
`54e932a90e45052b174b7d2bc9c98e34a18aa4ab`, before invoking the gate.

- [`clean-clone-370.log`](clean-clone-370.log) records a clean disposable
  clone running `bin/gate.sh` through the complete 370-test run.
- [`negative-required-nested.log`](negative-required-nested.log) records an
  unrestorable required nested member. The gate exits non-zero before Forge,
  and both Forge/compile and test-count scans match zero lines.

The amendment adds these proof files without changing the tested gate blob.
The committed attribution check is:

```text
$ git diff 38c5f8a2d319b317c2eab09de6e752346c1b1238 HEAD -- bin/gate.sh
EMPTY (no output)
```
