-- =====================================================================
-- Códex do Infinito · banco de dados (Supabase / Postgres)
-- Cole tudo no SQL Editor do Supabase e clique em RUN.
-- Pode rodar de novo sem perder dados: só cria o que ainda não existe
-- e atualiza as funções.
--
-- Segurança: o app NÃO lê nem grava as tabelas diretamente. Todas as
-- tabelas ficam fechadas (RLS ligado e sem permissões) e o app só usa as
-- funções abaixo, que conferem quem está pedindo (auth.uid()).
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tabelas ----------
create table if not exists public.turmas (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (char_length(nome) between 2 and 20),
  serie text not null check (serie in ('6', '7')),
  turno text not null check (turno in ('Manhã', 'Tarde')),
  codigo text not null unique,
  professor_id uuid not null references auth.users (id) on delete cascade,
  criada_em timestamptz not null default now()
);

create table if not exists public.perfis (
  id uuid primary key references auth.users (id) on delete cascade,
  usuario text not null unique,
  nick text not null,
  gm boolean not null default false,
  turma_id uuid references public.turmas (id) on delete set null,
  dados jsonb not null default '{}'::jsonb,
  nivel int not null default 0,
  xp int not null default 0,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create unique index if not exists perfis_nick_unico on public.perfis (lower(nick));
create index if not exists perfis_turma on public.perfis (turma_id);

create table if not exists public.partidas (
  id bigint generated always as identity primary key,
  aluno_id uuid not null references public.perfis (id) on delete cascade,
  tipo text not null check (tipo in ('arena', 'chefao', 'treino')),
  acertos int not null default 0 check (acertos between 0 and 100),
  total int not null default 0 check (total between 0 and 100),
  cont jsonb not null default '{}'::jsonb,
  criada_em timestamptz not null default now()
);
create index if not exists partidas_aluno on public.partidas (aluno_id, criada_em);

create table if not exists public.acessos (
  aluno_id uuid not null references public.perfis (id) on delete cascade,
  dia date not null default current_date,
  primary key (aluno_id, dia)
);

create table if not exists public.pedidos_nick (
  id bigint generated always as identity primary key,
  aluno_id uuid not null references public.perfis (id) on delete cascade,
  nick text not null,
  status text not null default 'pendente' check (status in ('pendente', 'aprovado', 'recusado')),
  criado_em timestamptz not null default now()
);

create table if not exists public.config (
  chave text primary key,
  valor text not null
);

-- Tabelas fechadas: só as funções (security definer) mexem nelas.
alter table public.turmas enable row level security;
alter table public.perfis enable row level security;
alter table public.partidas enable row level security;
alter table public.acessos enable row level security;
alter table public.pedidos_nick enable row level security;
alter table public.config enable row level security;
revoke all on public.turmas, public.perfis, public.partidas, public.acessos, public.pedidos_nick, public.config from anon, authenticated;

-- ---------- Funções de apoio (internas) ----------
create or replace function public._uid() returns uuid
language plpgsql stable as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'sem_login'; end if;
  return u;
end $$;

create or replace function public._eh_gm() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select gm from public.perfis where id = auth.uid()), false);
$$;

-- o aluno está numa turma deste professor?
create or replace function public._meu_aluno(p_aluno uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.perfis p join public.turmas t on t.id = p.turma_id
    where p.id = p_aluno and t.professor_id = auth.uid()
  );
$$;

create or replace function public._nick_ok(p_nick text) returns boolean
language sql immutable as $$
  select p_nick ~ '^[A-Za-z0-9]{4,14}$';
$$;

create or replace function public._codigo_novo() returns text
language plpgsql volatile as $$
declare letras text := 'ABCDEFGHJKLMNPQRSTUVWXYZ'; c text;
begin
  loop
    c := '';
    for i in 1..5 loop c := c || substr(letras, 1 + floor(random() * length(letras))::int, 1); end loop;
    exit when not exists (select 1 from public.turmas where codigo = c);
  end loop;
  return c;
end $$;

-- ---------- Funções do aluno ----------
create or replace function public.meu_perfil() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'usuario', p.usuario, 'nick', p.nick, 'gm', p.gm, 'dados', p.dados,
    'turma', (select json_build_object('id', t.id, 'nome', t.nome, 'serie', t.serie, 'turno', t.turno, 'codigo', t.codigo) from public.turmas t where t.id = p.turma_id),
    'pedido', (select r.nick from public.pedidos_nick r where r.aluno_id = p.id and r.status = 'pendente' order by r.id desc limit 1)
  )
  from public.perfis p where p.id = auth.uid();
$$;

create or replace function public.nick_livre(p_nick text) returns boolean
language sql stable security definer set search_path = public as $$
  select public._nick_ok(p_nick) and not exists (select 1 from public.perfis where lower(nick) = lower(p_nick));
$$;

create or replace function public.criar_perfil(p_nick text, p_dados jsonb) returns json
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid(); us text;
begin
  if exists (select 1 from public.perfis where id = u) then return public.meu_perfil(); end if;
  if not public._nick_ok(p_nick) then raise exception 'nick_invalido'; end if;
  if exists (select 1 from public.perfis where lower(nick) = lower(p_nick)) then raise exception 'nick_em_uso'; end if;
  if pg_column_size(p_dados) > 200000 then raise exception 'dados_grandes'; end if;
  select split_part(email, '@', 1) into us from auth.users where id = u;
  insert into public.perfis (id, usuario, nick, dados, nivel, xp)
  values (u, coalesce(us, u::text), p_nick, coalesce(p_dados, '{}'::jsonb),
          coalesce((p_dados ->> 'nivel')::int, 0), coalesce((p_dados ->> 'xp')::int, 0));
  insert into public.acessos (aluno_id) values (u) on conflict do nothing;
  return public.meu_perfil();
end $$;

create or replace function public.salvar_perfil(p_dados jsonb) returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid();
begin
  if pg_column_size(p_dados) > 200000 then raise exception 'dados_grandes'; end if;
  update public.perfis
     set dados = p_dados,
         nivel = least(greatest(coalesce((p_dados ->> 'nivel')::int, nivel), 0), 999),
         xp = greatest(coalesce((p_dados ->> 'xp')::int, xp), 0),
         atualizado_em = now()
   where id = u;
  return found;
end $$;

create or replace function public.registrar_acesso() returns void
language sql volatile security definer set search_path = public as $$
  insert into public.acessos (aluno_id)
  select id from public.perfis where id = auth.uid()
  on conflict do nothing;
$$;

create or replace function public.registrar_partida(p_tipo text, p_acertos int, p_total int, p_cont jsonb) returns void
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid();
begin
  if p_tipo not in ('arena', 'chefao', 'treino') then raise exception 'tipo_invalido'; end if;
  if p_total < 0 or p_total > 100 or p_acertos < 0 or p_acertos > p_total then raise exception 'numeros_invalidos'; end if;
  if pg_column_size(coalesce(p_cont, '{}'::jsonb)) > 5000 then raise exception 'dados_grandes'; end if;
  insert into public.partidas (aluno_id, tipo, acertos, total, cont)
  values (u, p_tipo, p_acertos, p_total, coalesce(p_cont, '{}'::jsonb));
  insert into public.acessos (aluno_id) values (u) on conflict do nothing;
end $$;

create or replace function public.entrar_turma(p_codigo text) returns json
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid(); t public.turmas;
begin
  select * into t from public.turmas where codigo = upper(trim(p_codigo));
  if not found then raise exception 'turma_nao_existe'; end if;
  update public.perfis set turma_id = t.id where id = u;
  return json_build_object('id', t.id, 'nome', t.nome, 'serie', t.serie, 'turno', t.turno, 'codigo', t.codigo);
end $$;

create or replace function public.pedir_nick(p_nick text) returns void
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid();
begin
  if not public.nick_livre(p_nick) then raise exception 'nick_em_uso'; end if;
  delete from public.pedidos_nick where aluno_id = u and status = 'pendente';
  insert into public.pedidos_nick (aluno_id, nick) values (u, p_nick);
end $$;

create or replace function public.apagar_minha_conta() returns void
language plpgsql volatile security definer set search_path = public, auth as $$
declare u uuid := public._uid();
begin
  delete from auth.users where id = u;
end $$;

-- ---------- Professor (GM) ----------
create or replace function public.virar_professor(p_codigo text) returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid();
begin
  if not exists (select 1 from public.config where chave = 'codigo_professor' and valor = p_codigo) then
    perform pg_sleep(1); -- atrasa quem tenta adivinhar
    raise exception 'codigo_errado';
  end if;
  update public.perfis set gm = true where id = u;
  return found;
end $$;

create or replace function public.criar_turma(p_nome text, p_serie text, p_turno text) returns json
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid(); t public.turmas;
begin
  if not public._eh_gm() then raise exception 'so_professor'; end if;
  insert into public.turmas (nome, serie, turno, codigo, professor_id)
  values (trim(p_nome), p_serie, p_turno, public._codigo_novo(), u) returning * into t;
  return json_build_object('id', t.id, 'nome', t.nome, 'serie', t.serie, 'turno', t.turno, 'codigo', t.codigo);
end $$;

create or replace function public.minhas_turmas() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._eh_gm() then raise exception 'so_professor'; end if;
  return coalesce((
    select json_agg(json_build_object(
      'id', t.id, 'nome', t.nome, 'serie', t.serie, 'turno', t.turno, 'codigo', t.codigo,
      'alunos', (
        select coalesce(json_agg(json_build_object(
          'id', p.id, 'nick', p.nick, 'nivel', p.nivel, 'xp', p.xp,
          'av', p.dados -> 'av', 'el', p.dados ->> 'el',
          'nc', coalesce((p.dados ->> 'nc')::int, p.nivel),
          'mol', coalesce(p.dados ->> 'moldura', ''),
          'liga', coalesce((p.dados -> 'liga' ->> 'idx')::int, 0),
          'dias', (select coalesce(json_agg(a.dia order by a.dia), '[]'::json) from public.acessos a where a.aluno_id = p.id and a.dia > current_date - 60),
          'acertos', (select coalesce(sum(x.acertos), 0) from public.partidas x where x.aluno_id = p.id),
          'total', (select coalesce(sum(x.total), 0) from public.partidas x where x.aluno_id = p.id),
          'partidas', (select count(*) from public.partidas x where x.aluno_id = p.id and x.tipo <> 'treino'),
          'cont', (
            select coalesce(json_object_agg(s.k, json_build_array(s.c, s.n)), '{}'::json) from (
              select e.key as k, sum((e.value ->> 0)::int) as c, sum((e.value ->> 1)::int) as n
              from public.partidas x, jsonb_each(x.cont) e
              where x.aluno_id = p.id and jsonb_typeof(e.value) = 'array'
              group by e.key
            ) s)
        ) order by p.nick), '[]'::json)
        from public.perfis p where p.turma_id = t.id),
      'pedidos', (
        select coalesce(json_agg(json_build_object('id', r.id, 'aluno_id', r.aluno_id, 'atual', p.nick, 'nick', r.nick) order by r.id), '[]'::json)
        from public.pedidos_nick r join public.perfis p on p.id = r.aluno_id
        where p.turma_id = t.id and r.status = 'pendente')
    ) order by t.criada_em)
    from public.turmas t where t.professor_id = auth.uid()
  ), '[]'::json);
end $$;

create or replace function public.decidir_pedido(p_id bigint, p_aprovar boolean) returns void
language plpgsql volatile security definer set search_path = public as $$
declare r public.pedidos_nick;
begin
  select * into r from public.pedidos_nick where id = p_id and status = 'pendente';
  if not found then raise exception 'pedido_nao_existe'; end if;
  if not public._meu_aluno(r.aluno_id) then raise exception 'nao_e_seu_aluno'; end if;
  if p_aprovar then
    if not public.nick_livre(r.nick) then raise exception 'nick_em_uso'; end if;
    update public.perfis set nick = r.nick where id = r.aluno_id;
  end if;
  update public.pedidos_nick set status = case when p_aprovar then 'aprovado' else 'recusado' end where id = p_id;
end $$;

create or replace function public.trocar_nick_aluno(p_aluno uuid, p_nick text) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if not public._meu_aluno(p_aluno) then raise exception 'nao_e_seu_aluno'; end if;
  if not public.nick_livre(p_nick) then raise exception 'nick_em_uso'; end if;
  update public.perfis set nick = p_nick where id = p_aluno;
end $$;

create or replace function public.redefinir_senha(p_aluno uuid, p_senha text) returns void
language plpgsql volatile security definer set search_path = public, extensions, auth as $$
begin
  if not public._meu_aluno(p_aluno) then raise exception 'nao_e_seu_aluno'; end if;
  if char_length(p_senha) < 6 then raise exception 'senha_curta'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_senha, extensions.gen_salt('bf')), updated_at = now() where id = p_aluno;
end $$;

create or replace function public.tirar_da_turma(p_aluno uuid) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if not public._meu_aluno(p_aluno) then raise exception 'nao_e_seu_aluno'; end if;
  update public.perfis set turma_id = null where id = p_aluno;
end $$;

-- ---------- Quem pode chamar o quê ----------
revoke all on all functions in schema public from public, anon;
grant execute on function
  public.meu_perfil(), public.nick_livre(text), public.criar_perfil(text, jsonb), public.salvar_perfil(jsonb),
  public.registrar_acesso(), public.registrar_partida(text, int, int, jsonb), public.entrar_turma(text),
  public.pedir_nick(text), public.apagar_minha_conta(), public.virar_professor(text), public.criar_turma(text, text, text),
  public.minhas_turmas(), public.decidir_pedido(bigint, boolean), public.trocar_nick_aluno(uuid, text),
  public.redefinir_senha(uuid, text), public.tirar_da_turma(uuid)
to authenticated;

-- ---------- Código secreto dos professores ----------
-- Por segurança, este arquivo NÃO cria o código. Depois de rodar, rode à parte
-- (trocando pelo seu código, com pelo menos 8 caracteres):
--   insert into public.config (chave, valor) values ('codigo_professor', 'SEU-CODIGO-AQUI')
--   on conflict (chave) do update set valor = excluded.valor;
-- Enquanto não houver código, ninguém consegue virar professor.
