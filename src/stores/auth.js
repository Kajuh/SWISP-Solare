import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'

export const useAuthStore = defineStore('auth', () => {
  const user = ref(null)
  const isAdmin = ref(false)
  const loading = ref(true)

  const isLoggedIn = computed(() => Boolean(user.value))

  async function refreshAdmin() {
    if (!user.value) {
      isAdmin.value = false
      return
    }
    const { data } = await supabase
      .from('admins')
      .select('user_id')
      .eq('user_id', user.value.id)
      .maybeSingle()
    isAdmin.value = Boolean(data)
  }

  async function init() {
    loading.value = true
    const { data } = await supabase.auth.getSession()
    user.value = data.session?.user ?? null
    await refreshAdmin()
    loading.value = false

    supabase.auth.onAuthStateChange(async (_event, session) => {
      user.value = session?.user ?? null
      await refreshAdmin()
    })
  }

  async function signIn(email, password) {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
    await refreshAdmin()
  }

  async function signOut() {
    await supabase.auth.signOut()
    user.value = null
    isAdmin.value = false
  }

  return { user, isAdmin, isLoggedIn, loading, init, signIn, signOut, refreshAdmin }
})
