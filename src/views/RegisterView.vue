<script setup>
import { ref, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '@/lib/supabase'
import { SPECIALIZATIONS } from '@/lib/labels'

const classes = ref([])
const nick = ref('')
const gameClass = ref('')
const spec = ref('')
const loading = ref(false)
const error = ref('')
const done = ref(false)

async function loadClasses() {
  const { data } = await supabase.from('classes').select('name').order('sort_order')
  classes.value = (data ?? []).map((c) => c.name)
}

async function submit() {
  error.value = ''
  if (!nick.value.trim()) return (error.value = 'Informe seu nick.')
  if (!gameClass.value) return (error.value = 'Escolha sua classe.')
  if (!spec.value) return (error.value = 'Escolha sua especialização.')
  loading.value = true
  const { error: e } = await supabase.rpc('register_player', {
    p_nick: nick.value.trim(),
    p_class: gameClass.value,
    p_spec: spec.value,
  })
  loading.value = false
  if (e) return (error.value = e.message)
  done.value = true
}

function reset() {
  nick.value = ''
  gameClass.value = ''
  spec.value = ''
  done.value = false
}

onMounted(loadClasses)
</script>

<template>
  <section style="max-width: 440px; margin: 32px auto">
    <div class="card grid" style="gap: 16px">
      <h1 style="margin: 0">Cadastro de jogador</h1>

      <template v-if="!done">
        <p class="muted" style="margin: 0">
          Cadastre-se para entrar nos campeonatos. Todo mundo começa com <strong>1000</strong> de pontuação.
          Você pode usar o mesmo nick em <strong>classes diferentes</strong> (um personagem por classe).
        </p>
        <form class="grid" style="gap: 14px" @submit.prevent="submit">
          <div>
            <label>Nick no jogo</label>
            <input v-model="nick" placeholder="Ex: Lestrad" maxlength="40" />
          </div>
          <div>
            <label>Classe</label>
            <select v-model="gameClass">
              <option value="" disabled>Selecione…</option>
              <option v-for="c in classes" :key="c" :value="c">{{ c }}</option>
            </select>
          </div>
          <div>
            <label>Especialização</label>
            <div class="flex" style="gap: 8px">
              <button
                v-for="s in SPECIALIZATIONS" :key="s.value" type="button"
                class="btn" :class="{ 'btn-primary': spec === s.value }"
                style="flex: 1; justify-content: center"
                @click="spec = s.value"
              >{{ s.label }}</button>
            </div>
          </div>
          <p v-if="error" class="error">{{ error }}</p>
          <button class="btn btn-primary" :disabled="loading">
            {{ loading ? 'Cadastrando…' : 'Cadastrar' }}
          </button>
        </form>
      </template>

      <template v-else>
        <p class="banner" style="margin: 0">✅ Cadastro feito! Você já aparece no ranking.</p>
        <div class="flex" style="gap: 10px">
          <RouterLink to="/" class="btn btn-primary">Ver ranking</RouterLink>
          <button class="btn" @click="reset">Cadastrar outro</button>
        </div>
      </template>
    </div>
  </section>
</template>
