# Portainer Assigned-Only Implementation Guide

## Goal

Ship a small Chatwoot fork that restricts non-admin agents to their own assigned conversations, validates the behavior in a local single-node Docker Swarm, and only then promotes a pinned custom image to Portainer.

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

- `CW_RESTRICT_AGENTS_TO_ASSIGNED_CONVERSATIONS` runtime toggle
- assigned-only backend enforcement
- minimal dashboard/runtime changes
- local Swarm deployment assets

## 3. Code Touchpoints

The feature is intentionally env-driven. When `CW_RESTRICT_AGENTS_TO_ASSIGNED_CONVERSATIONS=true`:

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

### Local files

- `deployment/swarm/chatwoot-local-assigned-only.stack.yml`
- `deployment/swarm/chatwoot-local-assigned-only.env.example`
- `script/chatwoot-local-swarm.sh`

### Build and deploy flow

1. Create a local env file from the example and adjust secrets.
2. Build and push the custom image to the local registry.
3. Deploy the Swarm stack.
4. Run `bundle exec rails db:chatwoot_prepare` inside the running Rails container.
5. Open the locally published URL and create the first admin user.

Example:

```bash
cp deployment/swarm/chatwoot-local-assigned-only.env.example deployment/swarm/chatwoot-local-assigned-only.env
script/chatwoot-local-swarm.sh
```

## 5. QA Matrix

Verify these cases locally with `CW_RESTRICT_AGENTS_TO_ASSIGNED_CONVERSATIONS=true`:

- Admin can still see all conversations.
- Agent A sees only conversations assigned to Agent A.
- Agent A cannot open Agent B's conversation directly by URL.
- Agent A cannot see unassigned conversations in list or search.
- Message search only returns messages from Agent A's assigned conversations.
- Bulk actions only mutate Agent A's assigned conversations.
- Sidebar hides `Mentions` and `Unattended`.
- Sidebar relabels `All Conversations` to `My Conversations`.

Then verify the toggle-off baseline:

- set `CW_RESTRICT_AGENTS_TO_ASSIGNED_CONVERSATIONS=false`
- redeploy locally
- confirm stock community behavior is unchanged

### Suggested local seed flow

After the first admin account exists:

```bash
docker exec -it $(docker ps --filter label=com.docker.swarm.service.name=chatwoot-local_rails -q | head -n1) \
  bundle exec rails runner "Seeders::AccountSeeder.new(account: Account.last).perform!"
```

Then create two agents and manually ensure the account contains:

- one conversation assigned to Agent A
- one conversation assigned to Agent B
- one unassigned conversation

## 6. Portainer Rollout

Do not change the VPS stack until the local Swarm flow passes.

Build a pinned production image, for example:

```text
ghcr.io/gustavohrg/chatwoot:<prod-tag>-assigned-only-v1
```

Update the Portainer stack:

- replace `chatwoot/chatwoot:latest` with the pinned custom image tag
- add `CW_RESTRICT_AGENTS_TO_ASSIGNED_CONVERSATIONS=true`
- replace `ENABLE_FORCE_SSL=true` with `FORCE_SSL=true`
- set the `internal` overlay network to `attachable: true`
- keep the existing Traefik labels and service names intact

Relevant production snippet:

```yaml
x-base: &base
  image: ghcr.io/gustavohrg/chatwoot:<prod-tag>-assigned-only-v1
  environment:
    - FORCE_SSL=true
    - CW_RESTRICT_AGENTS_TO_ASSIGNED_CONVERSATIONS=true
```

## 7. Rollback

Rollback is image-based, not container-edit based:

1. Revert the Portainer stack image tag to the previous pinned image.
2. Set `CW_RESTRICT_AGENTS_TO_ASSIGNED_CONVERSATIONS=false` or remove it.
3. Redeploy the stack.

Do not patch running containers in place.
