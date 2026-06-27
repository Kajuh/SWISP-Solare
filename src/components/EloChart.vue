<script setup>
import { computed } from 'vue'
import { Line } from 'vue-chartjs'
import {
  Chart as ChartJS,
  LineElement,
  PointElement,
  LinearScale,
  CategoryScale,
  Tooltip,
  Filler,
} from 'chart.js'

ChartJS.register(LineElement, PointElement, LinearScale, CategoryScale, Tooltip, Filler)

const props = defineProps({
  // pontos em ordem cronológica: [{ rating_after, created_at }]
  history: { type: Array, default: () => [] },
})

const chartData = computed(() => {
  // ponto inicial 1000 + cada partida
  const points = [1000, ...props.history.map((h) => h.rating_after)]
  return {
    labels: points.map((_, i) => (i === 0 ? 'início' : `#${i}`)),
    datasets: [
      {
        data: points,
        borderColor: '#e0a526',
        backgroundColor: 'rgba(224, 165, 38, 0.12)',
        borderWidth: 2,
        pointRadius: 3,
        pointBackgroundColor: '#e0a526',
        tension: 0.25,
        fill: true,
      },
    ],
  }
})

const options = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { display: false }, tooltip: { intersect: false, mode: 'index' } },
  scales: {
    x: { grid: { color: 'rgba(255,255,255,0.04)' }, ticks: { color: '#9aa3b8' } },
    y: { grid: { color: 'rgba(255,255,255,0.04)' }, ticks: { color: '#9aa3b8' } },
  },
}
</script>

<template>
  <div style="height: 260px">
    <Line :data="chartData" :options="options" />
  </div>
</template>
