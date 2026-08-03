# Security policy

## Sensitive data

ProxyBridge-TestLab may process environment-specific information such as:

- public and private IP addresses;
- local file paths;
- process names;
- proxy endpoints;
- proxy credentials;
- SSH destinations;
- packet captures;
- runtime logs.

Do not commit sensitive runtime data.

The following files and directories are ignored by default:

```text
.env
*.pbprofile
generated-profiles/
evidence/
logs/
captures/
dumps/
results/
```

Before publishing a commit, verify that it does not contain:

- passwords or access tokens;
- SSH private keys;
- private certificates;
- real proxy credentials;
- unredacted packet captures;
- unredacted production logs.

## Reporting a vulnerability

Do not include credentials, private keys, raw captures or other sensitive data
in a public issue.

Use GitHub private vulnerability reporting when it is enabled for the
repository. Otherwise, first open a minimal issue without sensitive details to
request a private contact method.

## Test safety

The test framework may:

- load ProxyBridge profiles;
- start or stop ProxyBridge CLI processes;
- change routing behavior;
- generate TCP and UDP traffic;
- restart services in explicitly destructive suites.

Run destructive scenarios only in an isolated test environment.

Do not execute experimental driver or lifecycle scenarios on a production
workstation.
