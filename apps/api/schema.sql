CREATE TABLE IF NOT EXISTS organizations (
  id text PRIMARY KEY, name text NOT NULL, city text NOT NULL
);
CREATE TABLE IF NOT EXISTS accounts (
  id text PRIMARY KEY, name text NOT NULL,
  role text NOT NULL CHECK(role IN ('captain','organizer')),
  organization_id text NOT NULL REFERENCES organizations(id)
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash text PRIMARY KEY, account_id text NOT NULL REFERENCES accounts(id),
  expires_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS teams (
  id text PRIMARY KEY, name text NOT NULL, city text NOT NULL,
  owner_id text NOT NULL REFERENCES accounts(id),
  organization_id text NOT NULL REFERENCES organizations(id),
  category text NOT NULL CHECK(category IN ('20cm','40cm')),
  roster jsonb NOT NULL CHECK(jsonb_typeof(roster) = 'array'),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS tournaments (
  id text PRIMARY KEY, title text NOT NULL, city text NOT NULL, venue text NOT NULL,
  organization_id text NOT NULL REFERENCES organizations(id),
  category text NOT NULL CHECK(category IN ('20cm','40cm')),
  starts_at timestamptz NOT NULL, deadline timestamptz NOT NULL,
  capacity integer NOT NULL CHECK(capacity BETWEEN 1 AND 128),
  description text NOT NULL, rules text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), CHECK(deadline < starts_at)
);
CREATE TABLE IF NOT EXISTS registrations (
  id text PRIMARY KEY, tournament_id text NOT NULL REFERENCES tournaments(id),
  team_id text NOT NULL REFERENCES teams(id), applicant_id text NOT NULL REFERENCES accounts(id),
  team_name text NOT NULL, roster jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
  review_note text NOT NULL DEFAULT '', reviewer_id text REFERENCES accounts(id),
  version integer NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz, UNIQUE(tournament_id,team_id)
);
CREATE INDEX IF NOT EXISTS registration_tournament ON registrations(tournament_id);
CREATE TABLE IF NOT EXISTS audit_log (
  id text PRIMARY KEY, actor_id text NOT NULL REFERENCES accounts(id),
  action text NOT NULL, resource_id text NOT NULL, detail jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
