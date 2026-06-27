<script setup>
import { ref, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '@/lib/supabase'

const events = ref([])
const loading = ref(true)

const statusLabel = { draft: 'Em montagem', active: 'Em andamento', finished: 'Encerrado' }

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('tournaments')
    .select('*, tournament_participants(count)')
    .order('created_at', { ascending: false })
  events.value = data ?? []
  loading.value = false
}
onMounted(load)
</script>

<template>
  <section>
    <h1>Eventos</h1>
    <p class="muted" style="margin-top: 4px">Sessões de partidas 3v3 aleatórias.</p>

    <p v-if="loading" class="empty">Carregando…</p>
    <p v-else-if="!events.length" class="empty">Nenhum evento criado ainda.</p>
    <div v-else class="grid" style="grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); margin-top: 16px">
      <RouterLink v-for="t in events" :key="t.id" :to="`/eventos/${t.id}`" class="card t-card">
        <div class="flex between">
          <h3 style="margin: 0">{{ t.name }}</h3>
          <span class="badge">{{ statusLabel[t.status] || t.status }}</span>
        </div>
        <p class="muted" style="margin: 10px 0 0">
          {{ t.tournament_participants?.[0]?.count ?? 0 }} participantes
          · +{{ t.win_points }} / −{{ t.loss_points }} (+{{ t.round_point }}/round)
        </p>
      </RouterLink>
    </div>
  </section>
</template>

<style scoped>
.t-card:hover { text-decoration: none; border-color: var(--accent); }
.t-card h3 { color: var(--text); }
</style>
