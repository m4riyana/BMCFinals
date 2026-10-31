-- Run in Supabase SQL Editor. Backend uses an atomic PostgreSQL document store.
CREATE TABLE IF NOT EXISTS public.ibasho_documents (
  collection text NOT NULL,
  id text NOT NULL,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (collection,id)
);
CREATE INDEX IF NOT EXISTS ibasho_docs_uid_idx ON public.ibasho_documents (collection,(data->>'uid'));
CREATE INDEX IF NOT EXISTS ibasho_docs_created_idx ON public.ibasho_documents (collection,(data->>'createdAt'));
ALTER TABLE public.ibasho_documents ENABLE ROW LEVEL SECURITY;
-- Public catalog reads only; all writes and private records go through authenticated backend.
DROP POLICY IF EXISTS "Public active product catalog" ON public.ibasho_documents;
CREATE POLICY "Public active product catalog" ON public.ibasho_documents
  FOR SELECT TO anon,authenticated USING (collection='products' AND data->>'isActive'='true');
DROP POLICY IF EXISTS "Public categories" ON public.ibasho_documents;
CREATE POLICY "Public categories" ON public.ibasho_documents
  FOR SELECT TO anon,authenticated USING (collection='categories');
-- No direct client write policies. Backend connects with a private Postgres DB credential.
