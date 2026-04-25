# Portainer Assigned-Only Implementation Guide

## Goal

Ship a small Chatwoot fork that restricts non-admin agents to their own assigned conversations, validates the behavior in a local single-node Docker Swarm, and only then promotes a pinned custom image to Portainer.

This guide uses Docker only for local validation. Do not treat host-level `pnpm dev`, `overmind`, or direct non-container app runs as part of the acceptance flow for this feature.

## 1. Freeze Production First

Do not build from this fork's `develop` branch and do not keep using `chatwoot/chatwoot:latest`.

Record the exact version currently running on the VPS before changing any code or image tags:

```bash
docker ps --format '{{.ID}} {{.Image}} {{.Names}}' | grep rails
docker exec <rails-container-id> cat /app/VERSION_CW
docker exec <rails-container-id> cat /app/.git_sha
```

Capture both values in the task notes. The custom worktree/branch must be created from the matching upstream tag or commit.

## 2. Fork Workflow

Add the upstream remote if this fork does not already have it:

```bash
git remote add upstream https://github.com/chatwoot/chatwoot.git
git fetch upstream --tags
```

Create a dedicated worktree from the exact production version:

```bash
git worktree add ../chatwoot-assigned-only -b feat/assigned-only-agent-restriction <matching-tag-or-sha>
```

Keep the fork diff narrow:

- assigned-only backend enforcement
- minimal dashboard/runtime changes
- local Swarm deployment assets

## 3. Code Touchpoints

The feature is enforced for all non-admin roles:

- non-admin agents can only list conversations assigned to themselves
- direct conversation access is denied unless `assignee_id == current_user.id`
- conversation search and message search only return self-assigned results
- bulk updates ignore conversation IDs outside the agent's self-assigned scope
- administrators keep the existing behavior

Primary files:

- `lib/chatwoot_app.rb`
- `app/services/conversations/permission_filter_service.rb`
- `enterprise/app/services/enterprise/conversations/permission_filter_service.rb`
- `app/policies/conversation_policy.rb`
- `app/services/search_service.rb`
- `enterprise/app/services/enterprise/search_service.rb`
- `app/jobs/bulk_actions_job.rb`
- `app/views/layouts/vueapp.html.erb`
- `app/javascript/dashboard/composables/useConfig.js`
- `app/javascript/dashboard/components/ChatList.vue`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`

## 4. Local Swarm Workflow

This repo includes a local Swarm stack that mirrors the current Portainer topology:

- `rails`
- `sidekiq`
- `chatwoot-postgres`
- `chatwoot-redis`

It uses:

- the same environment variable names as production
- the same split between web and worker services
- named volumes for storage, Redis, and Postgres
- an overlay `internal` network with `attachable: true`
- a locally published Rails port instead of Traefik
- containerized bootstrap and validation only

### Docker-only rule

For this feature, the local test environment is the Swarm stack only.

- start the app through `docker stack deploy`
- run bootstrap and seed commands through `docker exec`
- verify behavior through the browser against the running containers
- do not use host-run `rails s`, `sidekiq`, `pnpm dev`, or `overmind` as the test path

### Local files

- `deployment/swarm/chatwoot-local-assigned-only.stack.yml`
- `deployment/swarm/chatwoot-local-assigned-only.env.example`
- `script/chatwoot-local-swarm.sh`

### Build and deploy flow

1. Create a local env file from the example and adjust secrets.
2. Build and push the custom image to the local registry from `docker/Dockerfile`.
3. Deploy the Swarm stack.
4. Run `bundle exec rails db:chatwoot_prepare` through `docker exec` inside the running Rails container.
5. Open the locally published URL and create the first admin user.

Example:

```bash
cp deployment/swarm/chatwoot-local-assigned-only.env.example deployment/swarm/chatwoot-local-assigned-only.env
script/chatwoot-local-swarm.sh
```

All follow-up actions in this guide assume the stack is already running and are executed against that stack.

## 5. QA Matrix

Verify these cases locally:

- Admin can still see all conversations.
- Agent A sees only conversations assigned to Agent A.
- Agent A cannot open Agent B's conversation directly by URL.
- Agent A cannot see unassigned conversations in list or search.
- Message search only returns messages from Agent A's assigned conversations.
- Bulk actions only mutate Agent A's assigned conversations.
- Sidebar hides `Mentions` and `Unattended`.
- Sidebar relabels `All Conversations` to `My Conversations`.

These checks are Docker-only acceptance checks. Do not substitute them with direct host-level app runs.

### Suggested local seed flow

After the first admin account exists:

```bash
docker exec -it $(docker ps --filter label=com.docker.swarm.service.name=chatwoot-local_rails -q | head -n1) \
  bundle exec rails runner "Seeders::AssignedOnlyDemoSeeder.new(account: Account.last).perform!"
```

The minimal demo seed resets the account to the smallest useful assigned-only scenario:

- one inbox: `Assigned Only Demo Inbox`
- one existing administrator kept on the account
- two agent users
- three conversations total:
  - one assigned to Agent A
  - one assigned to Agent B
  - one unassigned

Demo logins:

- Agent A: `agent.a@assigned-only.demo.test`
- Agent B: `agent.b@assigned-only.demo.test`
- Password for both: `Password1!.`

### Docker-only acceptance sequence

1. Deploy the stack with `script/chatwoot-local-swarm.sh`.
2. Open `http://localhost:<RAILS_PORT>` in the browser.
3. Create the first admin user.
4. Seed the minimal demo data through `docker exec`.
5. Log in as `agent.a@assigned-only.demo.test` with password `Password1!.`.
6. Confirm Agent A sees exactly one conversation in `My Conversations`.
7. Log in as `agent.b@assigned-only.demo.test` with password `Password1!.`.
8. Confirm Agent B sees exactly one conversation in `My Conversations`.
9. Log in as the admin and confirm the admin sees all three conversations.
10. From the admin session, copy a conversation URL for Agent B and confirm Agent A cannot open it directly.
11. Verify search does not expose the other agent's conversation or the unassigned conversation.

No separate host-run acceptance flow is required for this guide.

## 6. Portainer Rollout

Do not change the VPS stack until the local Swarm flow passes.

Production deploy assets in this repo:

- `deployment/portainer/chatwoot-assigned-only.production.stack.yml`
- `deployment/portainer/chatwoot-assigned-only.production.env.example`
- `.github/workflows/publish_assigned_only_ghcr.yml`

### Publish the production image

Freeze production first and build from that exact upstream version, not from `latest`.

Then publish a pinned production image, for example:

```text
ghcr.io/gustavohrg/chatwoot:v4.12.1-assigned-only-v1
```

Recommended path:

1. Push this branch to GitHub.
2. Open GitHub Actions.
3. Run `Publish Assigned-Only Image to GHCR`.
4. Choose the exact branch or tag that matches the production freeze.
5. Set `image_tag` to something version-pinned such as `v4.12.1-assigned-only-v1`.
6. Keep `platforms` as `linux/amd64` unless you explicitly need multi-arch images.

Make sure Portainer can pull the GHCR image:

- either make the GHCR package public
- or add GHCR registry credentials in Portainer and attach them to the stack pull

### Update the Portainer stack

Your current stack editor content should change in these exact ways:

- replace `chatwoot/chatwoot:latest` with the pinned custom image tag
- replace `ENABLE_FORCE_SSL=true` with `FORCE_SSL=true`
- set the `internal` overlay network to `attachable: true`
- keep the existing Traefik labels and service names intact
- keep the same Postgres, Redis, volumes, and external `zirenet` network

Relevant production snippet:

```yaml
x-base: &base
  image: ghcr.io/gustavohrg/chatwoot:v4.12.1-assigned-only-v1
  environment:
    - FORCE_SSL=true
```

For your current Portainer stack, the exact stack-level diff is:

```diff
 x-base: &base
-  image: chatwoot/chatwoot:latest
+  image: ghcr.io/gustavohrg/chatwoot:v4.12.1-assigned-only-v1
   environment:
@@
-    - ENABLE_FORCE_SSL=true
+    - FORCE_SSL=true
@@
 networks:
   zirenet:
     external: true
   internal:
     driver: overlay
+    attachable: true
```

Use the provided template at `deployment/portainer/chatwoot-assigned-only.production.stack.yml` as the source of truth for the stack editor.

### Update the Portainer env values

Add these values to the Portainer environment editor:

```text
CHATWOOT_IMAGE=ghcr.io/gustavohrg/chatwoot:v4.12.1-assigned-only-v1
```

Keep your existing production secrets and SMTP settings unchanged unless you intend to rotate them.

### Migration note

This assigned-only fork does not add database migrations.

If you build from the exact same Chatwoot version already running in production, this feature rollout is an image swap plus env update only. No separate `db:chatwoot_prepare` step is required for this patch itself.

If you later upgrade Chatwoot to a newer upstream version, follow the normal Chatwoot upgrade process and run the matching database preparation step for that upgrade.

## 7. Rollback

Rollback is image-based, not container-edit based:

1. Revert the Portainer stack image tag to the previous pinned image.
2. Redeploy the stack.

Do not patch running containers in place.

## 8. Quick Redeploy Guide (New Feature)

When you've added a new feature on this worktree and need to redeploy to Portainer:

### Step 1: Publish the New Image

1. Push your branch to GitHub.
2. Go to **GitHub Actions** → `Publish Assigned-Only Image to GHCR`.
3. Run the workflow with:
   - **Branch/tag**: your feature branch
   - **image_tag**: a new version-pinned tag (e.g., `v4.12.1-assigned-only-v2`)
   - **platforms**: `linux/amd64`

### Step 2: Update Portainer Stack

In Portainer's stack editor, update the image tag:

```diff
 x-base: &base
-  image: ghcr.io/gustavohrg/chatwoot:<old-tag>
+  image: ghcr.io/gustavohrg/chatwoot:<new-tag>
```

### Step 3: Update Portainer Environment Variables

Update the environment editor with the new image tag:

```text
CHATWOOT_IMAGE=ghcr.io/gustavohrg/chatwoot:<new-tag>
```

### Step 4: Redeploy

Click **Update the stack** in Portainer to redeploy with the new image.

### Notes

- If the new feature adds database migrations, run `db:chatwoot_prepare` through `docker exec` after redeploying.
- Test locally with the Swarm stack first before deploying to production.
- Keep the previous image tag documented for quick rollback if needed.
