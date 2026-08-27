-- Constrain plano_producao.modo_colheita to its real domain.
--
-- 20260823001547 left this column as free text because the allowed values were
-- unknown, with a comment saying it owed a CHECK. The field team confirmed two
-- values: AXF and Espiga.
--
-- NULL remains permitted — the legacy column was nullable, and a plan may not
-- have the harvest mode decided yet. If it turns out to be mandatory, that is a
-- separate NOT NULL migration, not a widening of this constraint.
--
-- plano_producao is empty at the time of writing, so no existing row can
-- violate this. Should that change, add `not valid` and validate separately to
-- avoid a long table lock.

alter table public.plano_producao
  add constraint plano_modo_colheita_valido
  check (modo_colheita in ('AXF', 'Espiga'));

comment on column public.plano_producao.modo_colheita is
  'Harvest mode: AXF or Espiga. NULL until decided.';
