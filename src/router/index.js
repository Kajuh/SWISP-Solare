import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const routes = [
  { path: '/', name: 'leaderboard', component: () => import('@/views/LeaderboardView.vue') },
  { path: '/cadastro', name: 'register', component: () => import('@/views/RegisterView.vue') },
  { path: '/jogador/:id', name: 'player', component: () => import('@/views/PlayerView.vue'), props: true },
  { path: '/partidas', name: 'tournaments', component: () => import('@/views/TournamentsView.vue') },
  { path: '/partidas/:id', name: 'tournament', component: () => import('@/views/TournamentDetailView.vue'), props: true },
  { path: '/login', name: 'login', component: () => import('@/views/LoginView.vue') },
  {
    path: '/admin',
    name: 'admin',
    component: () => import('@/views/AdminView.vue'),
    meta: { requiresAdmin: true },
  },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 }),
})

router.beforeEach(async (to) => {
  if (!to.meta.requiresAdmin) return true
  const auth = useAuthStore()
  // Garante que a sessão já foi carregada antes de decidir
  while (auth.loading) await new Promise((r) => setTimeout(r, 30))
  if (!auth.isAdmin) return { name: 'login', query: { redirect: to.fullPath } }
  return true
})

export default router
