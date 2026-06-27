<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  labelA: { type: String, default: 'Time A' },
  labelB: { type: String, default: 'Time B' },
  bestOf: { type: Number, default: 5 },
})
const emit = defineEmits(['submit', 'cancel'])

const rounds = ref([]) // ['A','B','A', ...] em ordem
const needed = computed(() => Math.floor(props.bestOf / 2) + 1) // 3 num Bo5
const scoreA = computed(() => rounds.value.filter((r) => r === 'A').length)
const scoreB = computed(() => rounds.value.filter((r) => r === 'B').length)
const decided = computed(() => scoreA.value >= needed.value || scoreB.value >= needed.value)

function addWin(team) {
  if (decided.value) return
  rounds.value.push(team)
}
function undo() {
  rounds.value.pop()
}
function confirm() {
  if (decided.value) emit('submit', [...rounds.value])
}
</script>

<template>
  <div class="bo5">
    <div class="score">
      <span class="side">{{ labelA }}</span>
      <strong :class="{ win: scoreA >= needed }">{{ scoreA }}</strong>
      <span class="x">×</span>
      <strong :class="{ win: scoreB >= needed }">{{ scoreB }}</strong>
      <span class="side right">{{ labelB }}</span>
    </div>

    <p class="muted seq" v-if="rounds.length">
      Rounds:
      <template v-for="(r, i) in rounds" :key="i">
        <span class="r" :class="r === 'A' ? 'ra' : 'rb'">{{ r }}</span>
      </template>
    </p>
    <p class="muted seq" v-else>Marque o vencedor de cada round (melhor de {{ bestOf }}, fecha em {{ needed }}).</p>

    <div class="flex wrap" style="gap: 8px">
      <button class="btn btn-sm" :disabled="decided" @click="addWin('A')">+ round {{ labelA }}</button>
      <button class="btn btn-sm" :disabled="decided" @click="addWin('B')">+ round {{ labelB }}</button>
      <button class="btn btn-sm" :disabled="!rounds.length" @click="undo">Desfazer</button>
      <span style="flex: 1"></span>
      <button class="btn btn-sm" @click="emit('cancel')">Cancelar</button>
      <button class="btn btn-sm btn-primary" :disabled="!decided" @click="confirm">Confirmar resultado</button>
    </div>
  </div>
</template>

<style scoped>
.bo5 { background: var(--bg); border: 1px solid var(--border); border-radius: 9px; padding: 14px; }
.score { display: flex; align-items: center; justify-content: center; gap: 10px; font-size: 20px; margin-bottom: 8px; }
.score strong { min-width: 28px; text-align: center; }
.score strong.win { color: var(--accent); }
.side { font-size: 13px; color: var(--text-dim); max-width: 130px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.side.right { text-align: left; }
.x { color: var(--text-dim); }
.seq { margin: 4px 0 12px; }
.r { display: inline-flex; width: 18px; height: 18px; align-items: center; justify-content: center; border-radius: 4px; font-size: 11px; font-weight: 700; margin-right: 3px; }
.ra { background: rgba(224,165,38,0.2); color: var(--accent); }
.rb { background: rgba(91,141,239,0.2); color: var(--blue); }
</style>
