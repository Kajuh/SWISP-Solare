// Espelho da fórmula de ELO usada no servidor (supabase/migrations/0001_init.sql).
// Serve só para PREVER o resultado na tela do admin antes de confirmar.
// O cálculo que vale é sempre o do banco — este aqui é apenas informativo.

export function expectedScore(ratingA, ratingB) {
  return 1 / (1 + Math.pow(10, (ratingB - ratingA) / 400))
}

// Calcula o delta de cada lado em uma partida 3v3 usando a média dos times.
// winner: 'A' | 'B'. Retorna { deltaA, deltaB } (mesmo delta para todos do time).
export function previewDeltas(teamARatings, teamBRatings, winner, k = 32) {
  const avg = (arr) => arr.reduce((s, n) => s + n, 0) / arr.length
  const avgA = avg(teamARatings)
  const avgB = avg(teamBRatings)
  const eA = expectedScore(avgA, avgB)
  const eB = 1 - eA
  const sA = winner === 'A' ? 1 : 0
  const sB = 1 - sA
  return {
    deltaA: Math.round(k * (sA - eA)),
    deltaB: Math.round(k * (sB - eB)),
    expectedA: eA,
    expectedB: eB,
  }
}
