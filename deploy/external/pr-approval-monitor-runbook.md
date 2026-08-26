# PR Approval Monitor Runbook

This monitor is designed for an external Linux host. It performs read-only GitHub API checks and sends one Slack notification only after all 18 pull requests have two genuine approvals, an open state, `mergeable=true`, and `mergeable_state=clean`. It never creates approvals, closes pull requests, disables branch protection, or merges.

## Install

Clone the GitOps repository into `/opt/blueeconomy-platform-gitops`, create a dedicated `blueeconomy` system user, and install the repository-owned scripts with executable permissions. The host must provide Bash, GitHub CLI (`gh`) authenticated as a read-only or minimally scoped machine identity, `curl`, and `jq`.

```bash
sudo useradd --system --home /var/lib/blueeconomy --create-home --shell /usr/sbin/nologin blueeconomy
sudo install -d -o blueeconomy -g blueeconomy -m 0750 /opt/blueeconomy-platform-gitops /etc/blueeconomy /var/lib/blueeconomy
sudo cp -a . /opt/blueeconomy-platform-gitops/
sudo chown -R blueeconomy:blueeconomy /opt/blueeconomy-platform-gitops /var/lib/blueeconomy
sudo chmod 0755 /opt/blueeconomy-platform-gitops/scripts/check-pr-approvals.sh
sudo chmod 0755 /opt/blueeconomy-platform-gitops/scripts/approval-monitor-with-slack.sh
sudo chmod 0755 /opt/blueeconomy-platform-gitops/scripts/notify-pr-summary-slack.sh
```

Authenticate `gh` for the `blueeconomy` service account using the organization's approved secret-delivery mechanism. Do not put a token in the unit file, repository, shell history, or notification payload.

## Configure

Copy `secrets/external-runner-secrets.template` to `/etc/blueeconomy/pr-monitor.env`, keep only the monitor variables, set the Slack incoming-webhook URL through the host secret manager, and enforce mode `600`.

```bash
sudo install -o blueeconomy -g blueeconomy -m 0600 /dev/null /etc/blueeconomy/pr-monitor.env
sudoedit /etc/blueeconomy/pr-monitor.env
```

The minimum monitor configuration is:

```text
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/REDACTED
WATCH_SECONDS=300
PR_MONITOR_STATE_FILE=/var/lib/blueeconomy/all-prs-ready.sent
PR_MONITOR_MESSAGE_FILE=/var/lib/blueeconomy/pr-ready-message.txt
```

The redacted value above is illustrative only; retrieve the actual webhook from the approved secret manager. Never commit the completed file.

## Enable

Install the unit and start it only after the service account has read-only GitHub access and the Slack destination has been approved.

```bash
sudo cp deploy/external/blueeconomy-pr-approval-monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now blueeconomy-pr-approval-monitor.service
sudo systemctl status blueeconomy-pr-approval-monitor.service
sudo journalctl -u blueeconomy-pr-approval-monitor.service -f
```

The monitor exits each check with a blocked result until all requirements are satisfied, then posts one notification and creates the state marker. Remove the state marker only when a new approval cycle should produce a new notification.

## Disable and review

```bash
sudo systemctl disable --now blueeconomy-pr-approval-monitor.service
sudo journalctl -u blueeconomy-pr-approval-monitor.service --since today
```

Before production use, validate the service identity, GitHub token scope, Slack webhook ownership, host TLS trust, time synchronization, log retention, and incident response process. Do not run the service on the sandbox as a substitute for the external host; this workspace does not provide durable background hosting or the required external credentials.
