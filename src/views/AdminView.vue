<script setup>
import { ref, computed, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '@/lib/supabase'
import { specShort } from '@/lib/labels'
import Bo5Entry from '@/components/Bo5Entry.vue'

const tab = ref('eventos')

const players = ref([])
const events = ref([])
const msg = ref('')
const err = ref('')

function flash(text, isError = false) {
  if (isError) { err.value = text; msg.value = '' } else { msg.value = text; err.value = '' }
  setTimeout(() => { msg.value = ''; err.value = '' }, 4000)
}

async function loadAll() {
  const [{ data: pl }, { data: tr }] = await Promise.all([
    supabase.from('players').select('*').order('rating', { ascending: false }),
    supabase.from('tournaments').select('*').order('created_at', { ascending: false }),
  ])
  players.value = pl ?? []
  events.value = tr ?? []
}

/* ----------------------------- jogadores ------------------------------- */
async function removePlayer(p) {
  if (!confirm(`Excluir ${p.nick}? O histórico de partidas dele também será removido.`)) return
  const { error } = await supabase.from('players').delete().eq('id', p.id)
  if (error) return flash(error.message, true)
  await loadAll()
  flash('Jogador removido.')
}

/* -------------------------- partida avulsa ----------------------------- */
const teamA = ref([])
const teamB = ref([])
const winPoints = ref(20)
const lossPoints = ref(20)
const roundPoint = ref(5)
const pickSearch = ref('')
const showBo5 = ref(false)
const submitting = ref(false)

function assigned(id) {
  if (teamA.value.includes(id)) return 'A'
  if (teamB.value.includes(id)) return 'B'
  return null
}
function toggle(id, team) {
  const cur = assigned(id)
  teamA.value = teamA.value.filter((x) => x !== id)
  teamB.value = teamB.value.filter((x) => x !== id)
  if (cur !== team) (team === 'A' ? teamA : teamB).value.push(id)
  showBo5.value = false
}
function nickOf(id) { return players.value.find((p) => p.id === id)?.nick ?? '?' }
const availablePlayers = computed(() =>
  players.value.filter((p) => p.nick.toLowerCase().includes(pickSearch.value.toLowerCase()))
)
const canScore = computed(() => teamA.value.length > 0 && teamB.value.length > 0)

async function onBo5Submit(winners) {
  submitting.value = true
  const { error } = await supabase.rpc('create_ranked_match', {
    p_team_a: teamA.value,
    p_team_b: teamB.value,
    p_round_winners: winners,
    p_win_points: Number(winPoints.value),
    p_loss_points: Number(lossPoints.value),
    p_round_point: Number(roundPoint.value),
  })
  submitting.value = false
  if (error) return flash(error.message, true)
  teamA.value = []; teamB.value = []; showBo5.value = false
  await loadAll()
  flash('Partida registrada e pontuação atualizada!')
}

/* ------------------------------ eventos -------------------------------- */
const eName = ref('')
const eWin = ref(20)
const eLoss = ref(20)
const eRound = ref(5)

async function createEvent() {
  if (!eName.value.trim()) return flash('Dê um nome ao evento.', true)
  const { error } = await supabase.from('tournaments').insert({
    name: eName.value.trim(),
    win_points: Number(eWin.value),
    loss_points: Number(eLoss.value),
    round_point: Number(eRound.value),
  })
  if (error) return flash(error.message, true)
  eName.value = ''
  await loadAll()
  flash('Evento criado. Abra-o para adicionar participantes e sortear partidas.')
}

onMounted(loadAll)
</script>

<template>
  <section>
    <h1>Painel do administrador</h1>

    <div class="flex" style="gap: 8px; margin: 16px 0 20px">
      <button class="btn btn-sm" :class="{ 'btn-primary': tab === 'eventos' }" @click="tab = 'eventos'">Eventos</button>
      <button class="btn btn-sm" :class="{ 'btn-primary': tab === 'partida' }" @click="tab = 'partida'">Partida avulsa</button>
      <button class="btn btn-sm" :class="{ 'btn-primary': tab === 'jogadores' }" @click="tab = 'jogadores'">Jogadores</button>
    </div>

    <p v-if="msg" class="banner">{{ msg }}</p>
    <p v-if="err" class="banner" style="border-color: var(--red); color: var(--red); background: rgba(240,85,106,0.08)">{{ err }}</p>

    <!-- ================= EVENTOS ================= -->
    <div v-show="tab === 'eventos'" class="grid" style="gap: 16px">
      <div class="card">
        <h3 style="margin-top: 0">Criar evento</h3>
        <p class="muted" style="margin-top: 0">Pontuação: vencedor ganha os pontos de vitória; perdedor perde os de derrota, abatendo o desconto por round vencido.</p>
        <div class="flex wrap" style="align-items: flex-end">
          <div style="flex: 1; min-width: 200px">
            <label>Nome</label>
            <input v-model="eName" placeholder="Ex: Solare Night #1" />
          </div>
          <div style="width: 130px"><label>Pts vitória</label><input v-model="eWin" type="number" min="0" max="100" /></div>
          <div style="width: 130px"><label>Pts derrota</label><input v-model="eLoss" type="number" min="0" max="100" /></div>
          <div style="width: 150px"><label>Desconto/round</label><input v-model="eRound" type="number" min="0" max="30" /></div>
          <button class="btn btn-primary" @click="createEvent">Criar</button>
        </div>
      </div>

      <div class="card" style="padding: 0; overflow: hidden">
        <table>
          <thead><tr><th>Evento</th><th>Status</th><th>Pontuação</th><th></th></tr></thead>
          <tbody>
            <tr v-for="t in events" :key="t.id">
              <td>{{ t.name }}</td>
              <td><span class="badge">{{ t.status }}</span></td>
              <td class="muted">+{{ t.win_points }} / −{{ t.loss_points }} (+{{ t.round_point }}/round)</td>
              <td style="text-align: right">
                <RouterLink class="btn btn-sm" :to="`/eventos/${t.id}`">Gerenciar →</RouterLink>
              </td>
            </tr>
            <tr v-if="!events.length"><td colspan="4" class="empty">Nenhum evento.</td></tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- ================= PARTIDA AVULSA (Bo5) ================= -->
    <div v-show="tab === 'partida'" class="grid" style="gap: 16px">
      <div class="card">
        <h3 style="margin-top: 0">Partida avulsa (Bo5)</h3>
        <p class="muted" style="margin-top: 0">Escale os dois times manualmente e lance o placar round a round.</p>

        <div class="grid" style="grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 16px">
          <div class="team-box">
            <strong>Time A</strong>
            <div class="chips">
              <span v-for="id in teamA" :key="id" class="chip" @click="toggle(id, 'A')">{{ nickOf(id) }} ✕</span>
              <span v-if="!teamA.length" class="muted">vazio</span>
            </div>
          </div>
          <div class="team-box">
            <strong>Time B</strong>
            <div class="chips">
              <span v-for="id in teamB" :key="id" class="chip" @click="toggle(id, 'B')">{{ nickOf(id) }} ✕</span>
              <span v-if="!teamB.length" class="muted">vazio</span>
            </div>
          </div>
        </div>

        <input v-model="pickSearch" placeholder="Buscar jogador para escalar…" style="margin-bottom: 10px" />
        <div class="picker">
          <div v-for="p in availablePlayers" :key="p.id" class="picker-row">
            <span>{{ p.nick }} <span class="muted">· {{ p.game_class }} · {{ p.rating }}</span></span>
            <span class="flex" style="gap: 6px">
              <button class="btn btn-sm" :class="{ 'btn-primary': assigned(p.id) === 'A' }" @click="toggle(p.id, 'A')">A</button>
              <button class="btn btn-sm" :class="{ 'btn-primary': assigned(p.id) === 'B' }" @click="toggle(p.id, 'B')">B</button>
            </span>
          </div>
        </div>
      </div>

      <div class="card">
        <div class="flex wrap" style="align-items: flex-end; gap: 16px; margin-bottom: 14px">
          <div style="width: 120px"><label>Pts vitória</label><input v-model="winPoints" type="number" min="0" max="100" /></div>
          <div style="width: 120px"><label>Pts derrota</label><input v-model="lossPoints" type="number" min="0" max="100" /></div>
          <div style="width: 140px"><label>Desconto/round</label><input v-model="roundPoint" type="number" min="0" max="30" /></div>
          <button v-if="!showBo5" class="btn btn-primary" style="margin-left: auto" :disabled="!canScore" @click="showBo5 = true">
            Lançar placar →
          </button>
        </div>
        <Bo5Entry v-if="showBo5" :label-a="'Time A'" :label-b="'Time B'" @submit="onBo5Submit" @cancel="showBo5 = false" />
        <p v-if="submitting" class="muted">Salvando…</p>
      </div>
    </div>

    <!-- ================= JOGADORES (moderação) ================= -->
    <div v-show="tab === 'jogadores'" class="grid" style="gap: 16px">
      <p class="muted">O cadastro é feito pelos próprios membros em <RouterLink to="/cadastro">/cadastro</RouterLink>. Aqui você só modera (remover).</p>
      <div class="card" style="padding: 0; overflow: hidden">
        <table>
          <thead>
            <tr><th>Nick</th><th>Classe</th><th>Spec</th><th style="text-align: right">Pontos</th><th>V/D</th><th></th></tr>
          </thead>
          <tbody>
            <tr v-for="p in players" :key="p.id">
              <td><RouterLink :to="`/jogador/${p.id}`">{{ p.nick }}</RouterLink></td>
              <td class="muted">{{ p.game_class }}</td>
              <td class="muted">{{ specShort(p.specialization) }}</td>
              <td style="text-align: right; font-weight: 600">{{ p.rating }}</td>
              <td class="muted">{{ p.wins }}/{{ p.losses }}</td>
              <td style="text-align: right">
                <button class="btn btn-sm btn-danger" @click="removePlayer(p)">Excluir</button>
              </td>
            </tr>
            <tr v-if="!players.length"><td colspan="6" class="empty">Nenhum jogador.</td></tr>
          </tbody>
        </table>
      </div>
    </div>
  </section>
</template>

<style scoped>
.team-box { background: var(--bg-soft); border: 1px solid var(--border); border-radius: 9px; padding: 12px; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; min-height: 26px; }
.chip { background: var(--accent-soft); color: var(--accent); border-radius: 999px; padding: 3px 10px; font-size: 13px; font-weight: 600; cursor: pointer; }
.picker { max-height: 280px; overflow-y: auto; border: 1px solid var(--border); border-radius: 9px; }
.picker-row { display: flex; justify-content: space-between; align-items: center; padding: 8px 12px; border-bottom: 1px solid var(--border); }
.picker-row:last-child { border-bottom: none; }
</style>
