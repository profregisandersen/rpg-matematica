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
alter table public.perfis add column if not exists bloqueado boolean not null default false;
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
language plpgsql stable security definer set search_path = public as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'sem_login'; end if;
  if exists (select 1 from public.perfis where id = u and bloqueado) then raise exception 'conta_bloqueada'; end if;
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
    'usuario', p.usuario, 'nick', p.nick, 'gm', p.gm, 'dados', p.dados, 'bloqueado', p.bloqueado,
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
  perform public._sair_guilda(u);
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


-- =====================================================================
-- Guildas e Torre da Guilda (100 andares)
-- =====================================================================
create table if not exists public.guildas (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (char_length(nome) between 3 and 20),
  emblema jsonb not null default '{}'::jsonb,
  codigo text not null unique,
  serie text not null check (serie in ('6', '7')),
  lider_id uuid references public.perfis (id) on delete set null,
  andar int not null default 1,
  porta boolean not null default false,
  dano_andar int not null default 0,
  dano_total bigint not null default 0,
  criada_em timestamptz not null default now()
);
create unique index if not exists guildas_nome_unico on public.guildas (lower(nome));

create table if not exists public.guilda_membros (
  aluno_id uuid primary key references public.perfis (id) on delete cascade,
  guilda_id uuid not null references public.guildas (id) on delete cascade,
  entrou_em timestamptz not null default now()
);
create index if not exists guilda_membros_guilda on public.guilda_membros (guilda_id);

-- uma investida por aluno por dia (dia de Brasília)
create table if not exists public.investidas (
  id bigint generated always as identity primary key,
  aluno_id uuid not null references public.perfis (id) on delete cascade,
  guilda_id uuid not null references public.guildas (id) on delete cascade,
  andar int not null,
  dia date not null,
  acertos int not null default 0,
  dano int not null default 0,
  fechada boolean not null default false,
  criada_em timestamptz not null default now(),
  unique (aluno_id, dia)
);
create index if not exists investidas_guilda on public.investidas (guilda_id, andar);

create table if not exists public.andares_vencidos (
  guilda_id uuid not null references public.guildas (id) on delete cascade,
  andar int not null,
  vencido_em timestamptz not null default now(),
  primary key (guilda_id, andar)
);

alter table public.guildas enable row level security;
alter table public.guilda_membros enable row level security;
alter table public.investidas enable row level security;
alter table public.andares_vencidos enable row level security;
revoke all on public.guildas, public.guilda_membros, public.investidas, public.andares_vencidos from anon, authenticated;

create or replace function public._hoje() returns date
language sql stable as $$ select (now() at time zone 'America/Sao_Paulo')::date; $$;

-- vida do boss: 10.000 no andar 1 e +50 por andar (14.950 no andar 100)
create or replace function public._vida(p_andar int) returns int
language sql immutable as $$ select 10000 + 50 * (greatest(p_andar, 1) - 1); $$;

create or replace function public._serie_de(p_aluno uuid) returns text
language sql stable security definer set search_path = public as $$
  select t.serie from public.perfis p join public.turmas t on t.id = p.turma_id where p.id = p_aluno;
$$;

create or replace function public._guilda_de(p_aluno uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select guilda_id from public.guilda_membros where aluno_id = p_aluno;
$$;

create or replace function public._nome_guilda_ok(p_nome text) returns boolean
language sql immutable as $$
  select p_nome = btrim(p_nome) and char_length(p_nome) between 3 and 20
     and p_nome ~ '^[A-Za-z0-9ÀÁÂÃÇÉÊÍÓÔÕÚàáâãçéêíóôõú ]+$' and p_nome !~ '  ';
$$;

create or replace function public._codigo_guilda() returns text
language plpgsql volatile as $$
declare letras text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; c text;
begin
  loop
    c := '';
    for i in 1..6 loop c := c || substr(letras, 1 + floor(random() * length(letras))::int, 1); end loop;
    exit when not exists (select 1 from public.guildas where codigo = c);
  end loop;
  return c;
end $$;

create or replace function public.minha_guilda() returns json
language plpgsql stable security definer set search_path = public as $$
declare u uuid := public._uid(); g public.guildas;
begin
  select gg.* into g from public.guildas gg join public.guilda_membros m on m.guilda_id = gg.id where m.aluno_id = u;
  if not found then return null; end if;
  return json_build_object(
    'id', g.id, 'nome', g.nome, 'emblema', g.emblema, 'codigo', g.codigo, 'serie', g.serie,
    'andar', g.andar, 'porta', g.porta, 'dano_andar', g.dano_andar, 'vida', public._vida(g.andar), 'dano_total', g.dano_total,
    'lider', g.lider_id = u,
    'hoje', (select json_build_object('id', i.id, 'fechada', i.fechada, 'dano', i.dano, 'acertos', i.acertos)
             from public.investidas i where i.aluno_id = u and i.dia = public._hoje()),
    'membros', (
      select coalesce(json_agg(json_build_object(
        'id', p.id, 'nick', p.nick, 'gm', p.gm, 'av', p.dados -> 'av', 'mol', coalesce(p.dados ->> 'moldura', ''),
        'el', p.dados ->> 'el', 'nivel', p.nivel, 'lider', p.id = g.lider_id, 'voce', p.id = u,
        'dano_andar', (select coalesce(sum(i.dano), 0) from public.investidas i where i.aluno_id = p.id and i.guilda_id = g.id and i.andar = g.andar),
        'dano_total', (select coalesce(sum(i.dano), 0) from public.investidas i where i.aluno_id = p.id and i.guilda_id = g.id),
        'hoje', exists (select 1 from public.investidas i where i.aluno_id = p.id and i.dia = public._hoje())
      ) order by p.nick), '[]'::json)
      from public.guilda_membros m join public.perfis p on p.id = m.aluno_id where m.guilda_id = g.id)
  );
end $$;

create or replace function public.criar_guilda(p_nome text, p_emblema jsonb, p_serie text) returns json
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid(); s text; gid uuid;
begin
  if not exists (select 1 from public.perfis where id = u) then raise exception 'sem_perfil'; end if;
  if public._guilda_de(u) is not null then raise exception 'ja_tem_guilda'; end if;
  s := public._serie_de(u);
  if s is null then
    if public._eh_gm() and p_serie in ('6', '7') then s := p_serie; else raise exception 'sem_turma'; end if;
  end if;
  if not public._nome_guilda_ok(p_nome) then raise exception 'nome_invalido'; end if;
  if exists (select 1 from public.guildas where lower(nome) = lower(p_nome)) then raise exception 'nome_em_uso'; end if;
  if pg_column_size(coalesce(p_emblema, '{}'::jsonb)) > 400 then raise exception 'dados_grandes'; end if;
  insert into public.guildas (nome, emblema, codigo, serie, lider_id)
  values (p_nome, coalesce(p_emblema, '{}'::jsonb), public._codigo_guilda(), s, u) returning id into gid;
  insert into public.guilda_membros (aluno_id, guilda_id) values (u, gid);
  return public.minha_guilda();
end $$;

create or replace function public.entrar_guilda(p_codigo text) returns json
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid(); g public.guildas; s text;
begin
  if not exists (select 1 from public.perfis where id = u) then raise exception 'sem_perfil'; end if;
  if public._guilda_de(u) is not null then raise exception 'ja_tem_guilda'; end if;
  select * into g from public.guildas where codigo = upper(btrim(p_codigo)) for update;
  if not found then raise exception 'guilda_nao_existe'; end if;
  if (select count(*) from public.guilda_membros where guilda_id = g.id) >= 10 then raise exception 'guilda_cheia'; end if;
  if not public._eh_gm() then
    s := public._serie_de(u);
    if s is null then raise exception 'sem_turma'; end if;
    if s <> g.serie then raise exception 'outro_ano'; end if;
  end if;
  insert into public.guilda_membros (aluno_id, guilda_id) values (u, g.id);
  return public.minha_guilda();
end $$;

-- sai da guilda; se era o líder, a liderança passa para o membro de maior nível; guilda vazia é apagada
create or replace function public._sair_guilda(u uuid) returns void
language plpgsql volatile security definer set search_path = public as $$
declare gid uuid; novo uuid;
begin
  gid := public._guilda_de(u);
  if gid is null then return; end if;
  delete from public.guilda_membros where aluno_id = u;
  if (select lider_id from public.guildas where id = gid) is distinct from u then return; end if;
  select m.aluno_id into novo from public.guilda_membros m join public.perfis p on p.id = m.aluno_id
   where m.guilda_id = gid order by p.nivel desc, p.xp desc, m.entrou_em limit 1;
  if novo is null then delete from public.guildas where id = gid;
  else update public.guildas set lider_id = novo where id = gid; end if;
end $$;

create or replace function public.sair_guilda() returns void
language plpgsql volatile security definer set search_path = public as $$
begin perform public._sair_guilda(public._uid()); end $$;

-- o líder só apaga a guilda quando está sozinho nela
create or replace function public.apagar_guilda(p_confirma text) returns void
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid(); g public.guildas;
begin
  select * into g from public.guildas where id = public._guilda_de(u);
  if not found or g.lider_id is distinct from u then raise exception 'so_lider'; end if;
  if (select count(*) from public.guilda_membros where guilda_id = g.id) > 1 then raise exception 'guilda_com_membros'; end if;
  if lower(btrim(p_confirma)) <> lower(g.nome) then raise exception 'confirmacao_errada'; end if;
  delete from public.guildas where id = g.id;
end $$;

create or replace function public.passar_lideranca(p_aluno uuid) returns json
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid(); gid uuid := public._guilda_de(u);
begin
  if gid is null or (select lider_id from public.guildas where id = gid) is distinct from u then raise exception 'so_lider'; end if;
  if p_aluno = u or public._guilda_de(p_aluno) is distinct from gid then raise exception 'nao_e_membro'; end if;
  update public.guildas set lider_id = p_aluno where id = gid;
  return public.minha_guilda();
end $$;

create or replace function public.editar_guilda(p_nome text, p_emblema jsonb) returns json
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid(); gid uuid := public._guilda_de(u);
begin
  if gid is null or (select lider_id from public.guildas where id = gid) is distinct from u then raise exception 'so_lider'; end if;
  if not public._nome_guilda_ok(p_nome) then raise exception 'nome_invalido'; end if;
  if exists (select 1 from public.guildas where lower(nome) = lower(p_nome) and id <> gid) then raise exception 'nome_em_uso'; end if;
  if pg_column_size(coalesce(p_emblema, '{}'::jsonb)) > 400 then raise exception 'dados_grandes'; end if;
  update public.guildas set nome = p_nome, emblema = coalesce(p_emblema, emblema) where id = gid;
  return public.minha_guilda();
end $$;

create or replace function public.remover_membro(p_aluno uuid) returns json
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid(); gid uuid := public._guilda_de(u);
begin
  if gid is null or (select lider_id from public.guildas where id = gid) is distinct from u then raise exception 'so_lider'; end if;
  if p_aluno = u then raise exception 'use_sair'; end if;
  delete from public.guilda_membros where aluno_id = p_aluno and guilda_id = gid;
  if not found then raise exception 'nao_e_membro'; end if;
  return public.minha_guilda();
end $$;

create or replace function public.abrir_porta() returns json
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid(); gid uuid := public._guilda_de(u);
begin
  if gid is null or (select lider_id from public.guildas where id = gid) is distinct from u then raise exception 'so_lider'; end if;
  update public.guildas set porta = true where id = gid and andar <= 100;
  return public.minha_guilda();
end $$;

create or replace function public.iniciar_investida() returns json
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid(); g public.guildas; iid bigint;
begin
  select gg.* into g from public.guildas gg join public.guilda_membros m on m.guilda_id = gg.id where m.aluno_id = u;
  if not found then raise exception 'sem_guilda'; end if;
  if g.andar > 100 then raise exception 'torre_concluida'; end if;
  if not g.porta then raise exception 'porta_fechada'; end if;
  if exists (select 1 from public.investidas where aluno_id = u and dia = public._hoje()) then raise exception 'ja_investiu'; end if;
  insert into public.investidas (aluno_id, guilda_id, andar, dia) values (u, g.id, g.andar, public._hoje()) returning id into iid;
  return json_build_object('id', iid, 'andar', g.andar, 'vida', public._vida(g.andar), 'dano_andar', g.dano_andar);
end $$;

-- o dano é conferido por limites: até 60 acertos e no máximo 40 de dano por acerto
create or replace function public.finalizar_investida(p_id bigint, p_acertos int, p_dano int) returns json
language plpgsql volatile security definer set search_path = public as $$
declare u uuid := public._uid(); i public.investidas; g public.guildas; venceu int := null;
begin
  select * into i from public.investidas where id = p_id and aluno_id = u and not fechada for update;
  if not found then raise exception 'investida_invalida'; end if;
  if p_acertos < 0 or p_acertos > 60 or p_dano < 0 or p_dano > p_acertos * 40 then raise exception 'numeros_invalidos'; end if;
  select * into g from public.guildas where id = i.guilda_id for update;
  if not found or public._guilda_de(u) is distinct from g.id then
    update public.investidas set fechada = true where id = i.id;
    raise exception 'sem_guilda';
  end if;
  update public.investidas set acertos = p_acertos, dano = p_dano, fechada = true, andar = least(g.andar, 100) where id = i.id;
  if g.andar <= 100 and p_dano > 0 then
    g.dano_total := g.dano_total + p_dano;
    g.dano_andar := g.dano_andar + p_dano;
    if g.dano_andar >= public._vida(g.andar) then
      venceu := g.andar;
      insert into public.andares_vencidos (guilda_id, andar) values (g.id, g.andar) on conflict do nothing;
      g.andar := g.andar + 1; g.dano_andar := 0; g.porta := false;
    end if;
    update public.guildas set dano_total = g.dano_total, dano_andar = g.dano_andar, andar = g.andar, porta = g.porta where id = g.id;
  end if;
  if p_acertos > 0 then insert into public.acessos (aluno_id) values (u) on conflict do nothing; end if;
  return json_build_object('venceu', venceu, 'guilda', public.minha_guilda());
end $$;

-- rankings do ano escolar da guilda: andar mais alto, dano da guilda, jogadores com mais dano e pioneiros
create or replace function public.rankings_torre() returns json
language plpgsql stable security definer set search_path = public as $$
declare u uuid := public._uid(); s text;
begin
  s := coalesce((select serie from public.guildas where id = public._guilda_de(u)), public._serie_de(u));
  if s is null then return null; end if;
  return json_build_object(
    'serie', s,
    'andar', (select coalesce(json_agg(x), '[]'::json) from (
      select g.id, g.nome, g.emblema, least(g.andar, 101) as andar, g.dano_andar, public._vida(g.andar) as vida,
             (select count(*) from public.guilda_membros m where m.guilda_id = g.id) as membros
      from public.guildas g where g.serie = s order by g.andar desc, g.dano_andar desc, g.criada_em limit 10) x),
    'dano', (select coalesce(json_agg(x), '[]'::json) from (
      select g.id, g.nome, g.emblema, g.dano_total from public.guildas g where g.serie = s and g.dano_total > 0
      order by g.dano_total desc limit 10) x),
    'jogadores', (select coalesce(json_agg(x), '[]'::json) from (
      select p.id, p.nick, p.gm, p.dados -> 'av' as av, coalesce(p.dados ->> 'moldura', '') as mol, gg.nome as guilda, sum(i.dano) as dano
      from public.investidas i join public.guildas gg on gg.id = i.guilda_id join public.perfis p on p.id = i.aluno_id
      where gg.serie = s group by p.id, p.nick, p.gm, p.dados, gg.nome having sum(i.dano) > 0 order by sum(i.dano) desc limit 10) x),
    'pioneiros', (select coalesce(json_agg(x order by x.andar desc), '[]'::json) from (
      select distinct on (v.andar) v.andar, g.nome, v.vencido_em from public.andares_vencidos v join public.guildas g on g.id = v.guilda_id
      where g.serie = s order by v.andar, v.vencido_em) x)
  );
end $$;


-- =====================================================================
-- Administração (só GM): jogadores, guildas e registro das ações
-- =====================================================================
create table if not exists public.registro_admin (
  id bigint generated always as identity primary key,
  gm_id uuid references public.perfis (id) on delete set null,
  gm_nick text not null,
  acao text not null,
  alvo text not null,
  criado_em timestamptz not null default now()
);
alter table public.registro_admin enable row level security;
revoke all on public.registro_admin from anon, authenticated;

create or replace function public._so_gm() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare u uuid := public._uid();
begin
  if not public._eh_gm() then raise exception 'so_professor'; end if;
  return u;
end $$;

create or replace function public._registrar(p_acao text, p_alvo text) returns void
language sql volatile security definer set search_path = public as $$
  insert into public.registro_admin (gm_id, gm_nick, acao, alvo)
  select id, nick, p_acao, p_alvo from public.perfis where id = auth.uid();
$$;

create or replace function public.adm_jogadores() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._so_gm();
  return json_build_object(
    'jogadores', (select coalesce(json_agg(json_build_object(
      'id', p.id, 'usuario', p.usuario, 'nick', p.nick, 'gm', p.gm, 'bloqueado', p.bloqueado, 'nivel', p.nivel, 'xp', p.xp,
      'av', p.dados -> 'av', 'mol', coalesce(p.dados ->> 'moldura', ''), 'el', p.dados ->> 'el', 'criado', p.criado_em,
      'turma', (select json_build_object('id', t.id, 'nome', t.nome, 'serie', t.serie, 'turno', t.turno) from public.turmas t where t.id = p.turma_id),
      'guilda', (select g.nome from public.guilda_membros m join public.guildas g on g.id = m.guilda_id where m.aluno_id = p.id),
      'acesso', (select max(a.dia) from public.acessos a where a.aluno_id = p.id),
      'partidas', (select count(*) from public.partidas x where x.aluno_id = p.id)
    ) order by p.gm desc, lower(p.nick)), '[]'::json) from public.perfis p),
    'turmas', (select coalesce(json_agg(json_build_object('id', t.id, 'nome', t.nome, 'serie', t.serie, 'turno', t.turno, 'professor', (select nick from public.perfis where id = t.professor_id)) order by t.serie, t.nome), '[]'::json) from public.turmas t)
  );
end $$;

create or replace function public.adm_mudar_turma(p_aluno uuid, p_turma uuid) returns void
language plpgsql volatile security definer set search_path = public as $$
declare p public.perfis; t public.turmas;
begin
  perform public._so_gm();
  select * into p from public.perfis where id = p_aluno;
  if not found then raise exception 'nao_existe'; end if;
  if p.gm then raise exception 'alvo_gm'; end if;
  if p_turma is not null then
    select * into t from public.turmas where id = p_turma;
    if not found then raise exception 'turma_nao_existe'; end if;
  end if;
  update public.perfis set turma_id = p_turma where id = p_aluno;
  perform public._registrar('mudou de turma', p.nick || ' (' || p.usuario || ') → ' || coalesce(t.nome, 'sem turma'));
end $$;

create or replace function public.adm_bloquear(p_aluno uuid, p_bloquear boolean) returns void
language plpgsql volatile security definer set search_path = public as $$
declare p public.perfis;
begin
  perform public._so_gm();
  select * into p from public.perfis where id = p_aluno;
  if not found then raise exception 'nao_existe'; end if;
  if p.gm then raise exception 'alvo_gm'; end if;
  update public.perfis set bloqueado = p_bloquear where id = p_aluno;
  perform public._registrar(case when p_bloquear then 'bloqueou' else 'desbloqueou' end, p.nick || ' (' || p.usuario || ')');
end $$;

create or replace function public.adm_apagar_conta(p_aluno uuid, p_confirma text) returns void
language plpgsql volatile security definer set search_path = public, auth as $$
declare p public.perfis;
begin
  perform public._so_gm();
  select * into p from public.perfis where id = p_aluno;
  if not found then raise exception 'nao_existe'; end if;
  if p.gm then raise exception 'alvo_gm'; end if;
  if lower(btrim(p_confirma)) <> lower(p.usuario) then raise exception 'confirmacao_errada'; end if;
  perform public._sair_guilda(p_aluno);
  perform public._registrar('apagou a conta', p.nick || ' (' || p.usuario || ')');
  delete from auth.users where id = p_aluno;
end $$;

create or replace function public.adm_guildas() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._so_gm();
  return (select coalesce(json_agg(json_build_object(
    'id', g.id, 'nome', g.nome, 'emblema', g.emblema, 'serie', g.serie, 'codigo', g.codigo, 'andar', g.andar, 'dano_total', g.dano_total, 'criada', g.criada_em,
    'lider', (select nick from public.perfis where id = g.lider_id),
    'membros', (select coalesce(json_agg(p.nick order by lower(p.nick)), '[]'::json) from public.guilda_membros m join public.perfis p on p.id = m.aluno_id where m.guilda_id = g.id)
  ) order by g.serie, g.andar desc, lower(g.nome)), '[]'::json) from public.guildas g);
end $$;

create or replace function public.adm_renomear_guilda(p_guilda uuid, p_nome text) returns void
language plpgsql volatile security definer set search_path = public as $$
declare antigo text;
begin
  perform public._so_gm();
  select nome into antigo from public.guildas where id = p_guilda;
  if antigo is null then raise exception 'guilda_nao_existe'; end if;
  if not public._nome_guilda_ok(p_nome) then raise exception 'nome_invalido'; end if;
  if exists (select 1 from public.guildas where lower(nome) = lower(p_nome) and id <> p_guilda) then raise exception 'nome_em_uso'; end if;
  update public.guildas set nome = p_nome where id = p_guilda;
  perform public._registrar('renomeou a guilda', antigo || ' → ' || p_nome);
end $$;

create or replace function public.adm_apagar_guilda(p_guilda uuid, p_confirma text) returns void
language plpgsql volatile security definer set search_path = public as $$
declare g public.guildas;
begin
  perform public._so_gm();
  select * into g from public.guildas where id = p_guilda;
  if not found then raise exception 'guilda_nao_existe'; end if;
  if lower(btrim(p_confirma)) <> lower(g.nome) then raise exception 'confirmacao_errada'; end if;
  perform public._registrar('apagou a guilda', g.nome || ' (' || g.serie || 'º ano, andar ' || least(g.andar, 100) || ')');
  delete from public.guildas where id = p_guilda;
end $$;

create or replace function public.adm_registro() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._so_gm();
  return (select coalesce(json_agg(x order by x.criado_em desc), '[]'::json) from (
    select gm_nick, acao, alvo, criado_em from public.registro_admin order by criado_em desc limit 100) x);
end $$;

-- ---------- Quem pode chamar o quê ----------
revoke all on all functions in schema public from public, anon;
grant execute on function
  public.meu_perfil(), public.nick_livre(text), public.criar_perfil(text, jsonb), public.salvar_perfil(jsonb),
  public.registrar_acesso(), public.registrar_partida(text, int, int, jsonb), public.entrar_turma(text),
  public.pedir_nick(text), public.apagar_minha_conta(), public.virar_professor(text), public.criar_turma(text, text, text),
  public.minhas_turmas(), public.decidir_pedido(bigint, boolean), public.trocar_nick_aluno(uuid, text),
  public.redefinir_senha(uuid, text), public.tirar_da_turma(uuid),
  public.minha_guilda(), public.criar_guilda(text, jsonb, text), public.entrar_guilda(text), public.sair_guilda(),
  public.editar_guilda(text, jsonb), public.remover_membro(uuid), public.abrir_porta(), public.iniciar_investida(),
  public.finalizar_investida(bigint, int, int), public.rankings_torre(), public.apagar_guilda(text), public.passar_lideranca(uuid),
  public.adm_jogadores(), public.adm_mudar_turma(uuid, uuid), public.adm_bloquear(uuid, boolean), public.adm_apagar_conta(uuid, text),
  public.adm_guildas(), public.adm_renomear_guilda(uuid, text), public.adm_apagar_guilda(uuid, text), public.adm_registro()
to authenticated;

-- ---------- Código secreto dos professores ----------
-- Por segurança, este arquivo NÃO cria o código. Depois de rodar, rode à parte
-- (trocando pelo seu código, com pelo menos 8 caracteres):
--   insert into public.config (chave, valor) values ('codigo_professor', 'SEU-CODIGO-AQUI')
--   on conflict (chave) do update set valor = excluded.valor;
-- Enquanto não houver código, ninguém consegue virar professor.
