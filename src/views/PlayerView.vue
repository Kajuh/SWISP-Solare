<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '@/lib/supabase'
import EloChart from '@/components/EloChart.vue'
import { specLabel } from '@/lib/labels'

const props = defineProps({ id: { type: String, required: true } })

const player = ref(null)
const history = ref([])      // rating_history asc (para o gráfico)
const matches = ref([])      // partidas do jogador, desc (para a lista)
const loading = ref(true)
const error = ref('')

async function load() {
  loading.value = true
  error.value = ''
  const { data: p, error: e1 } = await supabase
    .from('players').select('*').eq('id', props.id).maybeSingle()
  if (e1) { error.value = e1.message; loading.value = false; return }
  player.value = p

  const { data: h } = await supabase
    .from('rating_history')
    .select('rating_before, rating_after, delta, created_at, match_id')
    .eq('player_id', props.id)
    .order('created_at', { ascending: true })
  history.value = h ?? []

  // Partidas em que o jogador entrou (com escalação completa para mostrar adversários)
  const { data: mine } = await supabase
    .from('match_players')
    .select('team, delta, rating_after, match:matches(id, winner, status, played_at, tournament_id)')
    .eq('player_id', props.id)
  const completed = (mine ?? []).filter((r) => r.match?.status === 'completed')
  const ids = completed.map((r) => r.match.id)

  let roster = []
  if (ids.length) {
    const { data: rs } = await supabase
      .from('match_players')
      .select('match_id, team, player:players(id, nick)')
      .in('match_id', ids)
    roster = rs ?? []
  }

  matches.value = completed
    .map((r) => {
      const others = roster.filter((x) => x.match_id === r.match.id && x.player.id !== props.id)
      return {
        id: r.match.id,
        won: r.team === r.match.winner,
        delta: r.delta,
        ratingAfter: r.rating_after,
        playedAt: r.match.played_at,
        isTournament: Boolean(r.match.tournament_id),
        teammates: others.filter((x) => x.team === r.team).map((x) => x.player),
        opponents: others.filter((x) => x.team !== r.team).map((x) => x.player),
      }
    })
    .sort((a, b) => new Date(b.playedAt) - new Date(a.playedAt))

  loading.value = false
}

const stats = computed(() => {
  if (!player.value) return null
  const total = player.value.wins + player.value.losses
  const peak = history.value.length
    ? Math.max(1000, ...history.value.map((h) => h.rating_after))
    : player.value.rating
  return {
    total,
    winrate: total ? Math.round((player.value.wins / total) * 100) : 0,
    peak,
  }
})

function fmtDate(d) {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' })
}

onMounted(load)
watch(() => props.id, load)
</script>

<template>
  <p v-if="loading" class="empty">Carregando…</p>
  <p v-else-if="error" class="error">{{ error }}</p>
  <p v-else-if="!player" class="empty">Jogador não encontrado.</p>

  <section v-else class="grid" style="gap: 20px">
    <RouterLink to="/" class="muted">← voltar ao ranking</RouterLink>

    <div class="card flex between wrap">
      <div>
        <h1 style="margin: 0">{{ player.nick }}</h1>
        <div class="flex" style="gap: 8px; margin-top: 8px">
          <span class="badge">{{ player.game_class }}</span>
          <span v-if="player.specialization" class="badge" style="background: rgba(91,141,239,0.15); color: var(--blue)">
            {{ specLabel(player.specialization) }}
          </span>
        </div>
      </div>
      <div class="flex" style="gap: 28px">
        <div class="stat"><div class="stat-v">{{ player.rating }}</div><div class="muted">Pontos</div></div>
        <div class="stat"><div class="stat-v">{{ stats.peak }}</div><div class="muted">Pico</div></div>
        <div class="stat"><div class="stat-v up">{{ player.wins }}</div><div class="muted">Vitórias</div></div>
        <div class="stat"><div class="stat-v down">{{ player.losses }}</div><div class="muted">Derrotas</div></div>
        <div class="stat"><div class="stat-v">{{ stats.winrate }}%</div><div class="muted">Winrate</div></div>
      </div>
    </div>

    <div class="card">
      <h3 style="margin-top: 0">Evolução dos pontos</h3>
      <EloChart v-if="history.length" :history="history" />
      <p v-else class="empty">Sem partidas registradas ainda.</p>
    </div>

    <div class="card" style="padding: 0; overflow: hidden">
      <h3 style="margin: 20px 20px 0">Histórico de partidas</h3>
      <p v-if="!matches.length" class="empty">Nenhuma partida finalizada.</p>
      <table v-else style="margin-top: 12px">
        <thead>
          <tr>
            <th>Data</th>
            <th>Resultado</th>
            <th>Aliados</th>
            <th>Adversários</th>
            <th style="text-align: right">ELO</th>
            <th style="text-align: right">Δ</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="m in matches" :key="m.id">
            <td class="muted">
              {{ fmtDate(m.playedAt) }}
              <span v-if="m.isTournament" class="badge" style="margin-left: 6px">torneio</span>
            </td>
            <td><span :class="m.won ? 'up' : 'down'">{{ m.won ? 'Vitória' : 'Derrota' }}</span></td>
            <td class="muted">
              <template v-for="(t, i) in m.teammates" :key="t.id">
                <RouterLink :to="`/jogador/${t.id}`">{{ t.nick }}</RouterLink><span v-if="i < m.teammates.length - 1">, </span>
              </template>
              <span v-if="!m.teammates.length">—</span>
            </td>
            <td class="muted">
              <template v-for="(o, i) in m.opponents" :key="o.id">
                <RouterLink :to="`/jogador/${o.id}`">{{ o.nick }}</RouterLink><span v-if="i < m.opponents.length - 1">, </span>
              </template>
            </td>
            <td style="text-align: right; font-weight: 600">{{ m.ratingAfter }}</td>
            <td style="text-align: right" :class="m.delta >= 0 ? 'up' : 'down'">
              {{ m.delta >= 0 ? '+' : '' }}{{ m.delta }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>

<style scoped>
.stat { text-align: center; }
.stat-v { font-size: 22px; font-weight: 700; }
</style>
