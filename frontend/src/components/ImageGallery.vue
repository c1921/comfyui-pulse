<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { Button } from '@/components/ui/button'
import type { CaptureFile } from '@/api'
import { fetchCaptures, subscribeEvents } from '@/api'

// ── State ──
const captures = ref<CaptureFile[]>([])
const newNames = ref<Set<string>>(new Set())
const loading = ref(true)
const previewFile = ref<CaptureFile | null>(null)
const previewIndex = ref(0)

// Directory handle for File System Access API
const directoryHandle = ref<FileSystemDirectoryHandle | null>(null)
const dirName = ref('')
const saveError = ref('')
const savingFiles = ref<Set<string>>(new Set())  // filenames currently being saved

let cleanupSse: (() => void) | null = null

// ── Helpers ──

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function formatTime(iso: string): string {
  const d = new Date(iso)
  return d.toLocaleString()
}

// ── File System Access API — pick directory ──

async function pickDirectory() {
  try {
    const handle = await window.showDirectoryPicker({ mode: 'readwrite' })
    directoryHandle.value = handle
    dirName.value = handle.name
    saveError.value = ''
    // Re-save any existing unsaved images
    for (const file of captures.value) {
      if (file.is_image && !file._saved) {
        trySaveImage(file)
      }
    }
  } catch (err: unknown) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      // user cancelled — not an error
      return
    }
    saveError.value = '无法访问目录：' + (err instanceof Error ? err.message : String(err))
  }
}

// ── File System Access API — write file ──

async function trySaveImage(file: CaptureFile) {
  if (!directoryHandle.value || savingFiles.value.has(file.name)) return
  savingFiles.value.add(file.name)
  try {
    const fileHandle = await directoryHandle.value.getFileHandle(file.name, { create: true })
    const writable = await fileHandle.createWritable()
    const resp = await fetch(file.path)
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
    const blob = await resp.blob()
    await writable.write(blob)
    await writable.close()
    file._saved = true
  } catch (err: unknown) {
    console.warn('Failed to save', file.name, err)
  } finally {
    savingFiles.value.delete(file.name)
  }
}

// ── Manual save (triggered by button click) ──

async function handleSave(file: CaptureFile) {
  if (!directoryHandle.value) {
    // No directory selected yet — prompt to pick one first
    await pickDirectory()
    // If user still didn't pick (cancelled), do nothing
    if (!directoryHandle.value) return
  }
  await trySaveImage(file)
}

// ── Lightbox navigation ──

const imageCaptures = computed(() => captures.value.filter((f) => f.is_image))

function openPreview(file: CaptureFile) {
  previewFile.value = file
  previewIndex.value = imageCaptures.value.findIndex((f) => f.name === file.name)
}

function closePreview() {
  previewFile.value = null
}

function prevImage() {
  const images = imageCaptures.value
  if (images.length === 0) return
  previewIndex.value = (previewIndex.value - 1 + images.length) % images.length
  previewFile.value = images[previewIndex.value]
}

function nextImage() {
  const images = imageCaptures.value
  if (images.length === 0) return
  previewIndex.value = (previewIndex.value + 1) % images.length
  previewFile.value = images[previewIndex.value]
}

function onPreviewKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape') closePreview()
  else if (e.key === 'ArrowLeft') { e.preventDefault(); prevImage() }
  else if (e.key === 'ArrowRight') { e.preventDefault(); nextImage() }
}

// ── Add new capture (from SSE or initial load) ──

function addCapture(file: CaptureFile, isNew: boolean) {
  // Avoid duplicates
  if (captures.value.some((c) => c.name === file.name)) return

  captures.value.unshift(file)
  if (isNew) {
    newNames.value.add(file.name)

    // Auto-save to selected directory using File System Access API
    if (directoryHandle.value && file.is_image) {
      trySaveImage(file)
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
  <div class="min-h-screen bg-zinc-950 text-zinc-100 p-6" @keydown="onPreviewKeydown">
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
          <template v-if="!directoryHandle">
            <Button variant="default" size="sm" @click="pickDirectory">
              选择保存目录
            </Button>
          </template>
          <template v-else>
            <div class="flex items-center gap-2 text-sm text-zinc-400">
              <svg class="w-4 h-4 text-emerald-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
              </svg>
              <span class="truncate max-w-[160px]">{{ dirName }}</span>
            </div>
          </template>
          <Button variant="outline" size="sm" @click="captures = []; newNames = new Set()">
            Clear
          </Button>
        </div>
      </div>

      <!-- Save directory prompt (when no directory selected but captures exist) -->
      <div
        v-if="!directoryHandle && captures.length > 0"
        class="mt-4 flex items-center gap-2 rounded-lg border border-amber-800/40 bg-amber-950/20 px-4 py-2.5 text-sm text-amber-300"
      >
        <svg class="w-5 h-5 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
        </svg>
        <span>选择保存目录后，新图片将自动写入本地文件夹</span>
      </div>

      <!-- Save error -->
      <div v-if="saveError" class="mt-2 text-sm text-red-400">{{ saveError }}</div>
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
        class="group relative rounded-xl border border-zinc-800 bg-zinc-900/50 overflow-hidden transition-all duration-300 cursor-pointer"
        :class="{
          'ring-2 ring-emerald-500/50 scale-[1.02]': newNames.has(file.name),
        }"
        @click="file.is_image ? openPreview(file) : null"
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
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
            </svg>
            <span class="text-xs truncate max-w-[120px]">{{ file.name }}</span>
          </div>
        </div>

        <!-- Hover overlay: save button (uses File System Access API) -->
        <button
          class="absolute top-2 right-2 flex items-center justify-center rounded-lg bg-black/60 p-2 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer hover:bg-black/80 z-10"
          title="保存到本地目录"
          @click.stop="handleSave(file)"
        >
          <svg
            v-if="!savingFiles.has(file.name)"
            class="w-5 h-5 text-white drop-shadow-lg"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
          </svg>
          <svg
            v-else
            class="w-5 h-5 text-emerald-400 animate-spin"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        </button>

        <!-- Saved badge -->
        <div
          v-if="file._saved"
          class="absolute top-2 left-2 rounded-full bg-emerald-500/80 px-2 py-0.5 text-xs text-white"
        >
          已保存
        </div>

        <!-- Info footer -->
        <div class="p-2.5 text-xs text-zinc-400">
          <p class="truncate font-medium text-zinc-300" :title="file.name">
            {{ file.name }}
          </p>
          <div class="flex justify-between mt-1">
            <span>{{ formatSize(file.size) }}</span>
            <span>{{ formatTime(file.mtime) }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Lightbox -->
    <Teleport to="body">
      <div
        v-if="previewFile"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/90"
        @click.self="closePreview"
      >
        <button
          class="absolute top-4 right-4 p-2 text-zinc-400 hover:text-white transition-colors"
          @click="closePreview"
        >
          <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>

        <button
          class="absolute left-4 top-1/2 -translate-y-1/2 p-2 text-zinc-400 hover:text-white transition-colors"
          @click="prevImage"
        >
          <svg class="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
        </button>

        <img
          :src="previewFile.path"
          :alt="previewFile.name"
          class="max-h-[90vh] max-w-[90vw] object-contain rounded-lg"
        />

        <button
          class="absolute right-4 top-1/2 -translate-y-1/2 p-2 text-zinc-400 hover:text-white transition-colors"
          @click="nextImage"
        >
          <svg class="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
          </svg>
        </button>

        <div class="absolute bottom-4 left-1/2 -translate-x-1/2 text-sm text-zinc-400">
          {{ previewIndex + 1 }} / {{ imageCaptures.length }}
        </div>
      </div>
    </Teleport>
  </div>
</template>
