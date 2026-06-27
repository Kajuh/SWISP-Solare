// Rótulos de exibição para a especialização do jogador.
export const SPECIALIZATIONS = [
  { value: 'sucessao', label: 'Sucessão', short: 'Suc' },
  { value: 'awakening', label: 'Awakening', short: 'Awk' },
  { value: 'ascensao', label: 'Ascensão', short: 'Asc' },
]

const map = Object.fromEntries(SPECIALIZATIONS.map((s) => [s.value, s]))

export function specLabel(value) {
  return map[value]?.label ?? '—'
}
export function specShort(value) {
  return map[value]?.short ?? '—'
}
