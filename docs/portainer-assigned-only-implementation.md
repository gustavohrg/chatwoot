# Assigned-only fork: local run and Portainer deployment runbook

This repository is already the Chatwoot fork. Do not recreate the fork, add a
new worktree, or rebuild the assigned-only feature from upstream for normal
development.

This runbook covers the repeatable workflow for this fork:

1. run and validate the fork locally in Docker Swarm;
2. publish a pinned image to GHCR;
3. update the Portainer stack;
4. roll back to the previous image when needed.

## Fork behavior

The intended product rule is:

- administrators can see all conversations;
- non-admin agents can see only conversations assigned to themselves;
- unassigned conversations are hidden from non-admin agents.

The local acceptance path is Docker Swarm only. Do not use host-run `rails s`,
`sidekiq`, `pnpm dev`, or `overmind` as a substitute for this validation.

## Local run

### Prerequisites

- Docker Engine with Buildx;
- a local Docker Swarm node;
- enough disk space for the Chatwoot image and PostgreSQL volume;
- ports `3300` and `5000` available, unless changed in the local env file.

Check Docker before starting:

```bash
docker version
docker buildx version
docker info --format '{{.Swarm.LocalNodeState}}'
```

The helper initializes a single-node Swarm when Swarm is not active. It also
starts a local registry on port `5000`.

### First setup

From repository root:

```bash
cp -n deployment/swarm/chatwoot-local-assigned-only.env.example \
  deployment/swarm/chatwoot-local-assigned-only.env
```

`-n` preserves an existing local env file. Edit the file if needed. At
minimum, replace `SECRET_KEY_BASE` with a generated value:

```bash
openssl rand -hex 64
```

Local defaults use:

- app URL: `http://localhost:3300`;
- image registry: `localhost:5000`;
- PostgreSQL service: `chatwoot-postgres`;
- Redis service: `chatwoot-redis`;
- Docker environment: `production` inside the container, matching the
  production image path.

### Build, deploy, and prepare database

Run:

```bash
script/chatwoot-local-swarm.sh
```

The script performs all local bootstrap steps:

1. validates the env, stack, and Dockerfile;
2. initializes Swarm if necessary;
3. starts `chatwoot-local-registry`;
4. builds `docker/Dockerfile` for `linux/amd64`;
5. pushes `localhost:5000/chatwoot:local-assigned-only`;
6. deploys stack `chatwoot-local`;
7. waits for Rails and runs `bundle exec rails db:chatwoot_prepare`.

The database preparation step creates tables only. It does not create a
Chatwoot account or administrator.

**Required order before seeding:**

1. Open `http://localhost:3300/installation/onboarding`.
2. Complete onboarding and create the first administrator.
3. Only after that, run the seed command below.

Running the seed before onboarding fails because `Account.last` is `nil`, with
`undefined method 'administrators' for nil`.

The script can be run again after code changes. It rebuilds the image, deploys
the stack, and repeats the idempotent database preparation step.

### Seed demo data

After completing onboarding and creating the first administrator, run the seed
command printed by the script:

```bash
RAILS_CONTAINER=$(docker ps \
  --filter 'label=com.docker.swarm.service.name=chatwoot-local_rails' \
  --format '{{.ID}}' | head -n1)

docker exec -it "$RAILS_CONTAINER" \
  bundle exec rails runner \
  'Seeders::AssignedOnlyDemoSeeder.new(account: Account.last).perform!'
```

This seeder is for the local demo account only. It deletes that account's
existing conversations, inboxes, contacts, labels, teams, and non-admin users
before creating demo data.

Demo logins:

- Agent A: `agent.a@assigned-only.demo.test` / `Password1!.`;
- Agent B: `agent.b@assigned-only.demo.test` / `Password1!.`.

### Validate assigned-only behavior

1. Agent A sees exactly one conversation.
2. Agent B sees exactly one different conversation.
3. Agents cannot open each other's conversation by direct URL.
4. Agents cannot see the unassigned conversation in the list or search.
5. Message search returns only messages from assigned conversations.
6. Bulk actions cannot mutate another agent's conversation.
7. The administrator sees all three conversations.
8. The sidebar hides `Mentions` and `Unattended` for non-admin agents and
   relabels `All Conversations` as `My Conversations`.

### Inspect or stop local stack

```bash
docker stack services chatwoot-local
docker service ps chatwoot-local_rails
docker service logs -f chatwoot-local_rails
docker service logs -f chatwoot-local_sidekiq
```

Stop application services while preserving named volumes:

```bash
docker stack rm chatwoot-local
```

Start again with `script/chatwoot-local-swarm.sh`. Do not remove the named
volumes unless you intentionally want to delete local database and storage
data.

## Publish a new version

Run local acceptance checks before publishing. Every production release must
use a new immutable image tag; never deploy `latest`.

### Choose image tag

Use the Chatwoot version plus an incrementing fork release suffix. Examples:

```text
v4.12.1-assigned-only-v1
v4.12.1-assigned-only-v2
```

Use a new suffix for every published image, even when the Chatwoot version is
unchanged. Record the previous tag for rollback.

### Publish through GitHub Actions

1. Commit and push the tested branch to `github.com/gustavohrg/chatwoot`.
2. Open **Actions** and select **Publish Assigned-Only Image to GHCR**.
3. Select **Run workflow** on the tested branch.
4. Set `image_tag` to the new pinned tag, such as
   `v4.12.1-assigned-only-v2`.
5. Keep `platforms` as `linux/amd64` unless another platform is required.
6. Wait for the workflow to finish successfully.

The workflow publishes:

```text
ghcr.io/gustavohrg/chatwoot:<image_tag>
```

If Portainer cannot pull the image, make the GHCR package public or configure
GHCR credentials in Portainer before updating the stack.

## Deploy new version in Portainer

Production stack source of truth:

- `deployment/portainer/chatwoot-assigned-only.production.stack.yml`;
- `deployment/portainer/chatwoot-assigned-only.production.env.example`.

### First Portainer setup

Create or update the stack using the production stack template. Keep the
existing production values for PostgreSQL, Redis, SMTP, storage, and
`zirenet`. Set:

```text
CHATWOOT_IMAGE=ghcr.io/gustavohrg/chatwoot:<pinned-tag>
```

The production template already contains the fork-specific settings:

- `FORCE_SSL=true`;
- `internal` overlay network with `attachable: true`;
- existing Traefik routing for `chatwoot.zireh.com.br`;
- Rails and Sidekiq services using the same image;
- persistent PostgreSQL, Redis, and storage volumes.

Do not replace production secrets with values from the example env file.

### Routine release

1. Record the currently deployed image tag.
2. Publish the new tag through GitHub Actions.
3. In Portainer, change only `CHATWOOT_IMAGE` to the new tag.
4. Click **Update the stack**.
5. Wait until Rails and Sidekiq report healthy/running.
6. Open the production URL and verify login, conversation access, sending,
   background jobs, and one assigned-only permission check.

Do not edit running containers. Deploy by changing the stack image tag.

### Database preparation

The current assigned-only implementation adds no database migrations. Updating
its image is therefore an image swap.

If a future release includes Chatwoot or fork migrations, run the matching
preparation command against the new Rails container after the stack update:

```bash
docker exec <rails-container-id> \
  bundle exec rails db:chatwoot_prepare
```

For an upstream Chatwoot version upgrade, follow the normal Chatwoot upgrade
process, including backups and its required database preparation.

## Rollback

Keep the previous image tag before every release. To roll back:

1. restore the previous `CHATWOOT_IMAGE` value in Portainer;
2. click **Update the stack**;
3. verify Rails, Sidekiq, login, and conversation access.

Code-only rollback is image-based. A release that changed the database schema
may require the normal database rollback/restore procedure; do not assume an
older image can use a newer schema.

## Production freeze and version identification

Before the first production release or an upstream upgrade, record the current
container image and Chatwoot build:

```bash
docker ps --format '{{.ID}} {{.Image}} {{.Names}}' | grep rails
docker exec <rails-container-id> cat /app/VERSION_CW
docker exec <rails-container-id> cat /app/.git_sha
```

Build releases from a reviewed branch in this fork. Do not build production
images from an unreviewed local working tree.
