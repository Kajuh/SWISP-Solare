<script setup>
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const email = ref('')
const password = ref('')
const error = ref('')
const loading = ref(false)

async function submit() {
  error.value = ''
  loading.value = true
  try {
    await auth.signIn(email.value, password.value)
    if (!auth.isAdmin) {
      error.value = 'Esta conta não é administradora. Adicione o user_id na tabela "admins".'
      await auth.signOut()
      return
    }
    router.push(route.query.redirect || '/admin')
  } catch (e) {
    error.value = e.message || 'Falha no login.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <section style="max-width: 380px; margin: 48px auto">
    <div class="card grid" style="gap: 16px">
      <h1 style="margin: 0">Entrar</h1>
      <p class="muted" style="margin: 0">Acesso restrito ao administrador.</p>
      <form class="grid" style="gap: 14px" @submit.prevent="submit">
        <div>
          <label>E-mail</label>
          <input v-model="email" type="email" autocomplete="email" required />
        </div>
        <div>
          <label>Senha</label>
          <input v-model="password" type="password" autocomplete="current-password" required />
        </div>
        <p v-if="error" class="error">{{ error }}</p>
        <button class="btn btn-primary" :disabled="loading">
          {{ loading ? 'Entrando…' : 'Entrar' }}
        </button>
      </form>
    </div>
  </section>
</template>
