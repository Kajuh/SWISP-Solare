<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import Bo5Entry from '@/components/Bo5Entry.vue'

const props = defineProps({ id: { type: String, required: true } })
const auth = useAuthStore()
const router = useRouter()

const event = ref(null)
const players = ref([])
const participantIds = ref([])
const matches = ref([])
const loading = ref(true)
const drawing = ref(false)
const msg = ref('')
const err = ref('')

function flash(text, isError = false) {
  if (isError) { err.value = text; msg.value = '' } else { msg.value = text; err.value = '' }
  setTimeout(() => { msg.value = ''; err.value = '' }, 4500)
}

async function load() {
  loading.value = true
  const [{ data: t }, { data: pl }, { data: pa }, { data: mt }] = await Promise.all([
    supabase.from('tournaments').select('*').eq('id', props.id).maybeSingle(),
    supabase.from('players').select('id, nick, game_class, rating').order('nick'),
    supabase.from('tournament_participants').select('player_id').eq('tournament_id', props.id),
    supabase
      .from('matches')
      .select('*, mp:match_players(team, delta, player:players(id, nick, game_class))')
      .eq('tournament_id', props.id)
      .order('created_at', { ascending: false }),
  ])
  event.value = t
  players.value = pl ?? []
  participantIds.value = (pa ?? []).map((x) => x.player_id)
  matches.value = mt ?? []
  loading.value = false
}

const current = computed(() => matches.value.find((m) => m.status === 'pending') || null)
const history = computed(() => matches.value.filter((m) => m.status === 'completed'))
const participantCount = computed(() => participantIds.value.length)

function roster(match, team) {
  return (match.mp ?? []).filter((x) => x.team === team).map((x) => x.player)
}

/* --------------------------- participantes ----------------------------- */
const search = ref('')
const filteredPlayers = computed(() =>
  players.value.filter((p) => p.nick.toLowerCase().includes(search.value.toLowerCase()))
)
function isParticipant(id) { return participantIds.value.includes(id) }
async function toggleParticipant(id) {
  if (isParticipant(id)) {
    const { error } = await supabase.from('tournament_participants')
      .delete().eq('tournament_id', props.id).eq('player_id', id)
    if (error) return flash(error.message, true)
    participantIds.value = participantIds.value.filter((x) => x !== id)
  } else {
    const { error } = await supabase.from('tournament_participants')
      .insert({ tournament_id: props.id, player_id: id })
    if (error) return flash(error.message, true)
    participantIds.value = [...participantIds.value, id]
  }
}

const statusLabel = { draft: 'Em montagem', active: 'Em andamento', finished: 'Encerrado' }
function fmtDate(d) {
  if (!d) return ''
  return new Date(d).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
}
function teamMp(m, team) { return (m.mp ?? []).filter((x) => x.team === team) }

/* ----------------------------- partidas -------------------------------- */
async function drawMatch() {
  drawing.value = true
  const { error } = await supabase.rpc('draw_random_match', { p_tournament_id: props.id, p_team_size: 3 })
  drawing.value = false
  if (error) return flash(error.message, true)
  // primeiro confronto sorteado: a partida passa a "Em andamento"
  if (event.value?.status === 'draft') {
    await supabase.from('tournaments').update({ status: 'active' }).eq('id', props.id)
  }
  await load()
  flash('Confronto sorteado!')
}
async function submitResult(match, winners) {
  const { error } = await supabase.rpc('set_match_result', { p_match_id: match.id, p_round_winners: winners })
  if (error) return flash(error.message, true)
  await load()
  flash('Resultado aplicado e pontuação atualizada.')
}
async function cancelMatch(match) {
  if (!confirm('Descartar este confronto sorteado (sem pontuar)?')) return
  const { error } = await supabase.from('matches').delete().eq('id', match.id)
  if (error) return flash(error.message, true)
  await load()
}
async function finishEvent() {
  await supabase.from('tournaments').update({ status: 'finished' }).eq('id', props.id)
  await load()
}
async function deleteEvent() {
  if (!confirm(`Remover "${event.value.name}"? Todos os confrontos dela serão apagados e os pontos revertidos.`)) return
  // remove cada confronto (revertendo os pontos) e depois a partida
  for (const m of matches.value) {
    await supabase.rpc('delete_match', { p_match_id: m.id })
  }
  const { error } = await supabase.from('tournaments').delete().eq('id', props.id)
  if (error) return flash(error.message, true)
  router.push('/partidas')
}
async function deleteMatch(match) {
  if (!confirm('Remover este confronto? Os pontos e o V/D dele serão revertidos.')) return
  const { error } = await supabase.rpc('delete_match', { p_match_id: match.id })
  if (error) return flash(error.message, true)
  await load()
  flash('Partida removida e pontos revertidos.')
}

onMounted(load)
watch(() => props.id, load)
</script>

<template>
  <p v-if="loading" class="empty">Carregando…</p>
  <p v-else-if="!event" class="empty">Partida não encontrada.</p>

  <section v-else class="grid" style="gap: 20px">
    <RouterLink to="/partidas" class="muted">← todas as partidas</RouterLink>
    <div class="flex between wrap">
      <div>
        <h1 style="margin: 0">{{ event.name }}</h1>
        <p class="muted" style="margin: 4px 0 0">
          Vitória +{{ event.win_points }} · Derrota −{{ event.loss_points }} (+{{ event.round_point }} por round vencido)
        </p>
      </div>
      <span class="badge">{{ statusLabel[event.status] || event.status }}</span>
    </div>

    <p v-if="msg" class="banner">{{ msg }}</p>
    <p v-if="err" class="banner" style="border-color: var(--red); color: var(--red); background: rgba(240,85,106,0.08)">{{ err }}</p>

    <!-- ===== Participantes (admin) ===== -->
    <div v-if="auth.isAdmin && event.status !== 'finished'" class="card">
      <h3 style="margin-top: 0">Participantes <span class="muted">({{ participantCount }})</span></h3>
      <p class="muted">Marque quem está jogando. Cada confronto sorteia 6 deles em 2 times de 3 (sem repetir classe no time).</p>
      <input v-model="search" placeholder="Buscar jogador…" style="margin-bottom: 10px" />
      <div class="pickers">
        <span
          v-for="p in filteredPlayers" :key="p.id"
          class="pk" :class="{ on: isParticipant(p.id) }" @click="toggleParticipant(p.id)"
        >{{ p.nick }} <span class="muted">{{ p.game_class }}</span></span>
        <span v-if="!filteredPlayers.length" class="muted">Nenhum jogador. Peça para se cadastrarem em /cadastro.</span>
      </div>
    </div>

    <!-- ===== Confronto em andamento (só aparece quando há um) ===== -->
    <div v-if="current" class="card">
      <h3 style="margin-top: 0">Confronto em andamento</h3>
      <div class="grid" style="grid-template-columns: 1fr auto 1fr; gap: 12px; align-items: center; margin-bottom: 14px">
        <div class="team-card a">
          <div class="team-h">Time A</div>
          <div v-for="p in roster(current, 'A')" :key="p.id">
            <RouterLink :to="`/jogador/${p.id}`">{{ p.nick }}</RouterLink>
            <span class="muted"> · {{ p.game_class }}</span>
          </div>
        </div>
        <div class="vs">VS</div>
        <div class="team-card b">
          <div class="team-h">Time B</div>
          <div v-for="p in roster(current, 'B')" :key="p.id">
            <RouterLink :to="`/jogador/${p.id}`">{{ p.nick }}</RouterLink>
            <span class="muted"> · {{ p.game_class }}</span>
          </div>
        </div>
      </div>
      <Bo5Entry
        v-if="auth.isAdmin"
        :label-a="'Time A'" :label-b="'Time B'" :best-of="current.best_of"
        @submit="(w) => submitResult(current, w)" @cancel="cancelMatch(current)"
      />
      <p v-else class="muted">Aguardando o resultado…</p>
    </div>

    <!-- Gerar nova partida (admin, quando não há nenhuma em andamento) -->
    <div v-else-if="auth.isAdmin && event.status !== 'finished'" class="card flex" style="gap: 12px; align-items: center">
      <button class="btn btn-primary" :disabled="participantCount < 6 || drawing" @click="drawMatch">
        🎲 {{ drawing ? 'Sorteando…' : 'Sortear confronto' }}
      </button>
      <span v-if="participantCount < 6" class="muted">Precisa de pelo menos 6 participantes.</span>
    </div>

    <!-- ===== Histórico ===== -->
    <div class="card">
      <h3 style="margin-top: 0">Histórico de confrontos <span class="muted">({{ history.length }})</span></h3>
      <p v-if="!history.length" class="empty">Nenhum confronto finalizado ainda.</p>
      <div v-else class="grid" style="gap: 12px">
        <div v-for="m in history" :key="m.id" class="hmatch">
          <div class="hmatch-head">
            <span class="muted">{{ fmtDate(m.played_at || m.created_at) }}</span>
            <span class="badge">Finalizada</span>
            <span style="flex: 1"></span>
            <button v-if="auth.isAdmin" class="btn btn-sm btn-danger" @click="deleteMatch(m)">Remover</button>
          </div>
          <div class="hmatch-body">
            <div class="hside" :class="{ win: m.winner === 'A' }">
              <div class="hside-h">Time A {{ m.winner === 'A' ? '🏆' : '' }}</div>
              <div v-for="mp in teamMp(m, 'A')" :key="mp.player.id" class="prow">
                <span class="nm">{{ mp.player.nick }}</span>
                <span :class="mp.delta >= 0 ? 'up' : 'down'">{{ mp.delta >= 0 ? '+' : '' }}{{ mp.delta }}</span>
              </div>
            </div>
            <div class="hscore">{{ m.rounds_a }} <span class="muted">×</span> {{ m.rounds_b }}</div>
            <div class="hside" :class="{ win: m.winner === 'B' }">
              <div class="hside-h">Time B {{ m.winner === 'B' ? '🏆' : '' }}</div>
              <div v-for="mp in teamMp(m, 'B')" :key="mp.player.id" class="prow">
                <span class="nm">{{ mp.player.nick }}</span>
                <span :class="mp.delta >= 0 ? 'up' : 'down'">{{ mp.delta >= 0 ? '+' : '' }}{{ mp.delta }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div v-if="auth.isAdmin" class="flex" style="gap: 8px">
      <button v-if="event.status !== 'finished'" class="btn btn-sm" @click="finishEvent">Encerrar</button>
      <button class="btn btn-sm btn-danger" @click="deleteEvent">Remover</button>
    </div>
  </section>
</template>

<style scoped>
.pickers { display: flex; flex-wrap: wrap; gap: 6px; }
.pk { background: var(--bg-soft); border: 1px solid var(--border); border-radius: 999px; padding: 4px 11px; font-size: 13px; cursor: pointer; }
.pk.on { background: var(--accent); color: #1a1405; border-color: var(--accent); }

.team-card { background: var(--bg-soft); border: 1px solid var(--border); border-radius: 9px; padding: 12px 14px; }
.team-card.a { border-left: 3px solid var(--accent); }
.team-card.b { border-left: 3px solid var(--blue); }
.team-h { font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-dim); margin-bottom: 8px; }
.vs { font-weight: 700; color: var(--text-dim); }
.winner { color: var(--accent); font-weight: 700; }

.hmatch { background: var(--bg-soft); border: 1px solid var(--border); border-radius: 9px; padding: 12px 14px; }
.hmatch-head { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; font-size: 13px; }
.hmatch-body { display: grid; grid-template-columns: 1fr auto 1fr; gap: 16px; align-items: start; }
.hside { display: grid; gap: 4px; }
.hside-h { font-size: 11px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-dim); margin-bottom: 4px; }
.hside.win .hside-h { color: var(--accent); }
.hside.win .nm { color: var(--accent); font-weight: 700; }
.prow { display: flex; justify-content: space-between; gap: 12px; }
.hscore { font-size: 22px; font-weight: 700; white-space: nowrap; padding-top: 18px; }
</style>
