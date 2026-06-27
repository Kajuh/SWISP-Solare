# ⚔ Solare Arena

Dashboard de campeonatos **3v3 (Arena of Solare)** de Black Desert, com **ranking ELO**,
perfil de jogador com evolução de pontos, e torneios com chaveamento.

- **Frontend:** Vue 3 + Vite + Pinia + Vue Router + Chart.js
- **Backend:** Supabase (Postgres + Auth + Realtime + Row Level Security)
- **Pontuação:** ELO clássico. Todos começam em **1000**. O ganho/perda usa a **média
  de rating de cada time** — favorito que vence ganha pouco; zebra ganha muito. O cálculo
  roda **no servidor** (função Postgres), então ninguém burla editando o navegador.

---

## 1. Pré-requisitos

- Node.js 18+ (testado com 20/24)
- Uma conta gratuita no [Supabase](https://supabase.com)

## 2. Configurar o Supabase

1. Crie um projeto novo em https://supabase.com/dashboard.
2. Vá em **SQL Editor** e rode, **nesta ordem**, o conteúdo de:
   - `supabase/migrations/0001_init.sql` (tabelas, RLS e função de ELO)
   - `supabase/migrations/0002_seed_classes.sql` (lista de classes)
   - `supabase/migrations/0003_functions.sql` (RPCs de partida e chaveamento)
   - `supabase/migrations/0004_changes.sql` (auto-cadastro, especialização, times aleatórios, Bo5)
3. Crie o usuário admin:
   - **Authentication → Users → Add user** (e-mail + senha). Confirme o e-mail.
   - Copie o `User UID` desse usuário.
   - No **SQL Editor**, rode (troque pelo UID copiado):
     ```sql
     insert into public.admins (user_id) values ('COLE-O-UID-AQUI');
     ```
4. Pegue as chaves em **Project Settings → API**:
   - `Project URL`
   - `anon public` key

## 3. Rodar o projeto

```bash
# 1. instalar dependências
npm install

# 2. configurar as variáveis de ambiente
cp .env.example .env
# edite .env e cole sua URL e a anon key

# 3. iniciar em desenvolvimento
npm run dev
```

Abra http://localhost:5173.

## 4. Como usar

- **/cadastro** — Página pública onde cada jogador se cadastra (nick + classe +
  especialização: Sucessão / Awakening / Ascensão). Todos entram com 1000.
- **/** — Ranking público por pontos (atualiza ao vivo), filtro por classe e busca.
- **/jogador/:id** — Perfil com gráfico de evolução dos pontos e histórico de partidas.
- **/eventos** — Lista de eventos (sessões de partidas 3v3 aleatórias).
- **/login → /admin** — Painel do administrador:
  - **Eventos:** criar → abrir → marcar **participantes** → **🎲 Gerar partida**
    (sorteia 6 em 2 times de 3, sem repetir classe no mesmo time) → lançar o
    placar **Bo5** → gerar a próxima. Partidas são independentes, sem chaveamento.
  - **Partida avulsa:** escale os dois times manualmente e lance o placar Bo5.
  - **Jogadores:** lista para moderação (remover). O cadastro em si é público.

## 5. Regras de pontuação

Pontuação **fixa** (não é ELO). Cada jogador, por partida:

```
Vitória:  + pts_vitória                                  (padrão +20)
Derrota:  - pts_derrota  +  desconto_round * rounds_vencidos   (padrão -20, +5/round)
```

- Exemplos de derrota (Bo5): 3×0 → −20 · 3×1 → −15 · 3×2 → −10.
- Os valores são configuráveis por evento e na partida avulsa.
- A pontuação nunca fica negativa (piso em 0).
- Vale para todas as partidas (evento e avulsa), pois o ranking é único.

## 6. Build de produção

```bash
npm run build      # gera dist/
npm run preview    # serve o build localmente
```

## Estrutura

```
supabase/migrations/   SQL do banco (rodar no SQL Editor do Supabase)
src/
  lib/        cliente Supabase + fórmula de ELO (prévia no front)
  stores/     auth (Pinia)
  router/     rotas + guard de admin
  views/      telas (Ranking, Jogador, Torneios, Admin, Login)
  components/  EloChart
```
