import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  // Mensagem clara em vez de um erro críptico de "fetch failed"
  console.error(
    '[Solare Arena] Variáveis do Supabase ausentes. ' +
      'Copie .env.example para .env e preencha VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY.'
  )
}

export const supabase = createClient(url ?? '', anonKey ?? '')
export const supabaseReady = Boolean(url && anonKey)
