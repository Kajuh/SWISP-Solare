<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '@/lib/supabase'
import { specShort } from '@/lib/labels'

const players = ref([])
const classes = ref([])
const classFilter = ref('')
const search = ref('')
const loading = ref(true)
const error = ref('')
let channel = null

async function load() {
  loading.value = true
  error.value = ''
  const [{ data: pl, error: e1 }, { data: cl }] = await Promise.all([
    supabase.from('players').select('*').order('rating', { ascending: false }),
    supabase.from('classes').select('name').order('sort_order'),
  ])
  if (e1) error.value = e1.message
  players.value = pl ?? []
  classes.value = (cl ?? []).map((c) => c.name)
  loading.value = false
}

const filtered = computed(() => {
  return players.value.filter((p) => {
    const okClass = !classFilter.value || p.game_class === classFilter.value
    const okSearch = !search.value || p.nick.toLowerCase().includes(search.value.toLowerCase())
    return okClass && okSearch
  })
})

function winrate(p) {
  const total = p.wins + p.losses
  return total ? Math.round((p.wins / total) * 100) : 0
}

onMounted(() => {
  load()
  // Ranking ao vivo: recarrega quando qualquer rating muda
  channel = supabase
    .channel('players-live')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'players' }, load)
    .subscribe()
})
onUnmounted(() => channel && supabase.removeChannel(channel))
</script>

<template>
  <section>
    <div class="flex between wrap" style="margin-bottom: 20px">
      <div>
        <h1>Ranking</h1>
        <p class="muted" style="margin: 4px 0 0">
          Classificação por pontos — todos começam em 1000. Atualiza ao vivo.
        </p>
      </div>
      <div class="flex wrap">
        <input v-model="search" placeholder="Buscar nick…" style="width: 180px" />
        <select v-model="classFilter" style="width: 170px">
          <option value="">Todas as classes</option>
          <option v-for="c in classes" :key="c" :value="c">{{ c }}</option>
        </select>
      </div>
    </div>

    <div class="card" style="padding: 0; overflow: hidden">
      <p v-if="error" class="error" style="padding: 16px">{{ error }}</p>
      <p v-else-if="loading" class="empty">Carregando ranking…</p>
      <p v-else-if="!filtered.length" class="empty">Nenhum jogador cadastrado ainda.</p>
      <table v-else>
        <thead>
          <tr>
            <th style="width: 56px">#</th>
            <th>Jogador</th>
            <th>Classe</th>
            <th style="text-align: right">Pontos</th>
            <th style="text-align: center">V</th>
            <th style="text-align: center">D</th>
            <th style="text-align: right">Winrate</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(p, i) in filtered" :key="p.id">
            <td>
              <span :class="['rank', { top: i < 3 && !classFilter && !search }]">{{ i + 1 }}</span>
            </td>
            <td>
              <svg v-if="i < 3 && !classFilter && !search" class="crown" :class="`c${i}`" viewBox="0 0 24 22" aria-hidden="true">
                <path d="M2 6 L7 11 L12 3 L17 11 L22 6 L20 19 L4 19 Z" />
              </svg>
              <RouterLink :to="`/jogador/${p.id}`" class="nick">{{ p.nick }}</RouterLink>
            </td>
            <td>
              <span class="muted">{{ p.game_class }}</span>
              <span v-if="p.specialization" class="spec">{{ specShort(p.specialization) }}</span>
            </td>
            <td style="text-align: right; font-weight: 700">{{ p.rating }}</td>
            <td style="text-align: center" class="up">{{ p.wins }}</td>
            <td style="text-align: center" class="down">{{ p.losses }}</td>
            <td style="text-align: right">{{ winrate(p) }}%</td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>

<style scoped>
.nick { font-weight: 600; }
.rank {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px; height: 28px;
  border-radius: 8px;
  font-weight: 700;
  background: var(--bg-soft);
}
.rank.top { background: var(--accent); color: #1a1405; }
.spec { margin-left: 6px; font-size: 11px; font-weight: 700; color: var(--blue); border: 1px solid var(--border); border-radius: 5px; padding: 1px 5px; }
.crown {
  width: 16px; height: 15px; margin-right: 6px; vertical-align: -2px;
  stroke: rgba(0, 0, 0, 0.35); stroke-width: 1;
  filter: drop-shadow(0 1px 1px rgba(0, 0, 0, 0.4));
}
.crown.c0 { fill: #f4c84b; } /* ouro */
.crown.c1 { fill: #cbd2dc; } /* prata */
.crown.c2 { fill: #cd7f32; } /* bronze */
</style>
