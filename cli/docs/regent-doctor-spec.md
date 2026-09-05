# Regent Doctor

`regents doctor` diagnoses the repository-owned local runtime and surviving authentication boundary without constructing a legacy Techtree client.

## Scopes

- `runtime`: config loading, local directories, runtime socket, and Platform contract compatibility
- `auth`: saved identity and SIWA session readiness, signature-envelope construction, and verification transport
- `transports`: local gossipsub configuration

The default and full modes use these same non-destructive checks. The former remote Techtree probes and mutation proof are not part of the shipped doctor.

## Safety

Doctor checks do not publish content, create remote records, move money, modify wallet or signer state, or contact an old Techtree endpoint. `--fix` is limited to safe local repairs already described by command help.

## SIWA configuration

SIWA message construction uses `config.services.platform.baseUrl` as the verification URI and that URL's host as the signing domain. The SIWA service URL remains transport configuration only.

## Verification

```bash
regents doctor --json
regents doctor runtime --json
regents doctor auth --json
regents doctor transports --json
```

Each result reports its check id, scope, status, detail, and remediation when applicable.
