create schema api;

create role authenticator noinherit login password 'mysecretpassword';

create role anon noinherit;
grant anon to authenticator;
grant usage on schema api to anon;

create role member noinherit;
grant member to authenticator;
grant usage on schema api to member;

create role dev_admin nologin;
grant usage on schema api to dev_admin;
grant dev_admin to authenticator;

alter default privileges in schema api grant all on TABLES TO dev_admin;
alter default privileges in schema api grant all on SEQUENCES TO dev_admin;
alter default privileges in schema api grant all on FUNCTIONS TO dev_admin;

alter default privileges in schema api grant SELECT, UPDATE, INSERT, DELETE on TABLES TO member;
alter default privileges in schema api grant SELECT, UPDATE on SEQUENCES TO member;

-- Automatic reloading of schema on ddl_command_end
-- Create an event trigger function
CREATE OR REPLACE FUNCTION pgrst_watch() RETURNS event_trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  NOTIFY pgrst, 'reload schema';
END;
$$;

-- This event trigger will fire after every ddl_command_end event
CREATE EVENT TRIGGER pgrst_watch
  ON ddl_command_end
  EXECUTE PROCEDURE pgrst_watch();