<script setup>
import { RouterLink, RouterView, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { supabaseReady } from '@/lib/supabase'

const auth = useAuthStore()
const router = useRouter()

async function logout() {
  await auth.signOut()
  router.push('/')
}
</script>

<template>
  <header class="topbar">
    <div class="topbar-inner container">
      <RouterLink to="/" class="brand">
        <span class="brand-mark">⚔</span>
        <span>Solare<strong>Arena</strong></span>
      </RouterLink>
      <nav class="nav">
        <RouterLink to="/">Ranking</RouterLink>
        <RouterLink to="/partidas">Partidas</RouterLink>
        <RouterLink to="/cadastro">Cadastrar</RouterLink>
        <RouterLink v-if="auth.isAdmin" to="/admin">Admin</RouterLink>
        <a v-if="auth.isAdmin" href="#" @click.prevent="logout">Sair</a>
        <RouterLink v-else to="/login">Entrar</RouterLink>
      </nav>
    </div>
  </header>

  <main class="container">
    <div v-if="!supabaseReady" class="banner">
      ⚠ Supabase não configurado. Crie um arquivo <code>.env</code> com
      <code>VITE_SUPABASE_URL</code> e <code>VITE_SUPABASE_ANON_KEY</code> (veja o README).
    </div>
    <RouterView />
  </main>
</template>

<style scoped>
.topbar {
  background: var(--bg-soft);
  border-bottom: 1px solid var(--border);
  position: sticky;
  top: 0;
  z-index: 10;
}
.topbar-inner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-top: 14px;
  padding-bottom: 14px;
}
.brand {
  display: flex;
  align-items: center;
  gap: 9px;
  font-size: 19px;
  font-weight: 600;
  color: var(--text);
}
.brand:hover { text-decoration: none; }
.brand strong { color: var(--accent); }
.brand-mark {
  color: var(--accent);
  font-size: 22px;
}
.nav { display: flex; gap: 20px; align-items: center; }
.nav a { color: var(--text-dim); font-weight: 600; font-size: 14px; }
.nav a:hover { color: var(--text); text-decoration: none; }
.nav a.router-link-exact-active { color: var(--accent); }
code { background: rgba(0,0,0,0.25); padding: 1px 5px; border-radius: 5px; font-size: 0.9em; }
</style>
