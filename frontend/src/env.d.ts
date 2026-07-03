/// <reference types="vite/client" />

/** File System Access API — Directory picker */
interface FileSystemDirectoryHandle {
  name: string
  getFileHandle(name: string, options?: { create?: boolean }): Promise<FileSystemFileHandle>
}

interface FileSystemFileHandle {
  createWritable(): Promise<FileSystemWritableFileStream>
}

interface FileSystemWritableFileStream extends WritableStream {
  write(data: Blob | FileSystemWriteChunkType): Promise<void>
  close(): Promise<void>
}

interface Window {
  showDirectoryPicker(options?: { mode?: 'read' | 'readwrite' }): Promise<FileSystemDirectoryHandle>
}
