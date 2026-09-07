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

CREATE TABLE IF NOT EXISTS community_posts (
  id text PRIMARY KEY, author_id text NOT NULL REFERENCES accounts(id),
  kind text NOT NULL CHECK(kind IN ('recruit','seeking','friendly','volunteer')),
  title text NOT NULL, city text NOT NULL, category text NOT NULL CHECK(category IN ('20cm','40cm')),
  level text NOT NULL, availability text NOT NULL, venue text NOT NULL, body text NOT NULL,
  team_id text REFERENCES teams(id), starts_at timestamptz,
  status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','matched','closed','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS community_applications (
  id text PRIMARY KEY, post_id text NOT NULL REFERENCES community_posts(id),
  applicant_id text NOT NULL REFERENCES accounts(id), team_id text REFERENCES teams(id),
  message text NOT NULL, status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','accepted','rejected','withdrawn')),
  created_at timestamptz NOT NULL DEFAULT now(), reviewed_at timestamptz,
  UNIQUE(post_id,applicant_id)
);
CREATE TABLE IF NOT EXISTS team_members (
  team_id text NOT NULL REFERENCES teams(id), account_id text NOT NULL REFERENCES accounts(id),
  joined_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(team_id,account_id)
);
CREATE INDEX IF NOT EXISTS community_posts_kind ON community_posts(kind,created_at);
CREATE INDEX IF NOT EXISTS community_applications_owner ON community_applications(applicant_id);
CREATE TABLE IF NOT EXISTS community_messages (
  id text PRIMARY KEY, application_id text NOT NULL REFERENCES community_applications(id),
  sender_id text NOT NULL REFERENCES accounts(id), body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS community_messages_application ON community_messages(application_id,created_at);

CREATE TABLE IF NOT EXISTS community_message_reads (
  message_id text NOT NULL REFERENCES community_messages(id), account_id text NOT NULL REFERENCES accounts(id),
  PRIMARY KEY(message_id,account_id)
);
CREATE TABLE IF NOT EXISTS feedback (
  id text PRIMARY KEY, account_id text NOT NULL REFERENCES accounts(id),
  category text NOT NULL, body text NOT NULL, status text NOT NULL DEFAULT 'received',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS matches (
  id text PRIMARY KEY, tournament_id text NOT NULL REFERENCES tournaments(id),
  home_registration_id text NOT NULL REFERENCES registrations(id), away_registration_id text NOT NULL REFERENCES registrations(id),
  starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL, venue text NOT NULL, stage text NOT NULL,
  status text NOT NULL CHECK(status IN ('scheduled','final','cancelled')),
  home_score integer, away_score integer, note text NOT NULL DEFAULT '', version integer NOT NULL DEFAULT 1,
  CHECK(home_registration_id<>away_registration_id), CHECK(ends_at>starts_at),
  CHECK((status='final' AND home_score BETWEEN 0 AND 999 AND away_score BETWEEN 0 AND 999 AND home_score IS NOT NULL AND away_score IS NOT NULL)
    OR (status<>'final' AND home_score IS NULL AND away_score IS NULL))
);
CREATE INDEX IF NOT EXISTS matches_tournament ON matches(tournament_id,starts_at);
