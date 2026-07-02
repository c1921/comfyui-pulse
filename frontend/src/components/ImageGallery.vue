<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { Button } from '@/components/ui/button'
import type { CaptureFile } from '@/api'
import { fetchCaptures, subscribeEvents } from '@/api'

// ── State ──
const captures = ref<CaptureFile[]>([])
const newNames = ref<Set<string>>(new Set())
const autoDownload = ref(true)
const loading = ref(true)
let cleanupSse: (() => void) | null = null

// ── Helpers ──

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function formatTime(iso: string): string {
  const d = new Date(iso)
  return d.toLocaleTimeString()
}

function triggerDownload(file: CaptureFile) {
  const a = document.createElement('a')
  a.href = file.path
  a.download = file.name
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
}

// ── Add new capture (from SSE or initial load) ──

function addCapture(file: CaptureFile, isNew: boolean) {
  // Avoid duplicates
  if (captures.value.some((c) => c.name === file.name)) return

  captures.value.unshift(file)
  if (isNew) {
    newNames.value.add(file.name)

    // Auto-download if enabled and it's an image
    if (autoDownload.value) {
      triggerDownload(file)
    }

    // Remove highlight after animation
    setTimeout(() => {
      newNames.value.delete(file.name)
    }, 3000)
  }
}

// ── Lifecycle ──

onMounted(async () => {
  // Load existing captures
  try {
    const list = await fetchCaptures()
    for (const item of list) {
      addCapture(item, false)
    }
  } catch {
    // Backend might not be running yet
  } finally {
    loading.value = false
  }

  // Subscribe to real-time events
  cleanupSse = subscribeEvents((file) => {
    addCapture(file, true)
  })
})

onUnmounted(() => {
  cleanupSse?.()
})
</script>

<template>
  <div class="min-h-screen bg-zinc-950 text-zinc-100 p-6">
    <!-- Header -->
    <div class="max-w-6xl mx-auto mb-8">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Capture Gallery</h1>
          <p class="text-sm text-zinc-400 mt-1">
            {{ captures.length }} file{{ captures.length !== 1 ? 's' : '' }} received
            <span v-if="loading" class="ml-2 text-zinc-500">loading…</span>
          </p>
        </div>
        <div class="flex items-center gap-3">
          <label class="flex items-center gap-2 text-sm cursor-pointer select-none">
            <input
              v-model="autoDownload"
              type="checkbox"
              class="accent-emerald-500 h-4 w-4 rounded"
            />
            Auto-download
          </label>
          <Button
            variant="outline"
            size="sm"
            @click="captures = []; newNames = new Set()"
          >
            Clear
          </Button>
        </div>
      </div>
    </div>

    <!-- Empty state -->
    <div
      v-if="!loading && captures.length === 0"
      class="max-w-6xl mx-auto flex flex-col items-center justify-center py-24 text-zinc-500"
    >
      <svg
        class="w-16 h-16 mb-4 opacity-40"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909M3.75 21h16.5A2.25 2.25 0 0022.5 18.75V5.25A2.25 2.25 0 0020.25 3H3.75A2.25 2.25 0 001.5 5.25v13.5A2.25 2.25 0 003.75 21z"
        />
      </svg>
      <p class="text-lg">Waiting for captures…</p>
      <p class="text-sm mt-1">Send an HTTP request to the capture server to see it here.</p>
    </div>

    <!-- Grid -->
    <div
      v-if="captures.length > 0"
      class="max-w-6xl mx-auto grid gap-4 grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4"
    >
      <div
        v-for="file in captures"
        :key="file.name"
        class="group relative rounded-xl border border-zinc-800 bg-zinc-900/50 overflow-hidden transition-all duration-300"
        :class="{
          'ring-2 ring-emerald-500/50 scale-[1.02]': newNames.has(file.name),
        }"
      >
        <!-- Image preview -->
        <div class="aspect-square bg-zinc-800 flex items-center justify-center overflow-hidden">
          <img
            v-if="file.is_image"
            :src="file.path"
            :alt="file.name"
            class="w-full h-full object-cover transition-opacity group-hover:opacity-80"
            loading="lazy"
          />
          <div v-else class="flex flex-col items-center text-zinc-500">
            <svg class="w-10 h-10 mb-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="1.5"
                d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z"
              />
            </svg>
            <span class="text-xs truncate max-w-[120px]">{{ file.name }}</span>
          </div>

          <!-- Download overlay -->
          <button
            class="absolute inset-0 flex items-center justify-center bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer"
            @click="triggerDownload(file)"
          >
            <svg class="w-8 h-8 text-white drop-shadow-lg" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
              />
            </svg>
          </button>
        </div>

        <!-- Info bar -->
        <div class="p-2.5 text-xs text-zinc-400">
          <p class="truncate font-medium text-zinc-300" :title="file.name">{{ file.name }}</p>
          <div class="flex justify-between mt-1">
            <span>{{ formatSize(file.size) }}</span>
            <span>{{ formatTime(file.mtime) }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
