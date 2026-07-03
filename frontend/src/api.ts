/**
 * API client for the backend capture server.
 *
 * - Fetches initial list of captures via GET /api/captures
 * - Connects to SSE at /api/events for real-time updates
 */

export interface CaptureFile {
  name: string
  path: string
  size: number
  mtime: string
  content_type: string
  is_image: boolean
  _saved?: boolean
}

export interface CapturesResponse {
  captures: CaptureFile[]
}

export type CaptureEventHandler = (file: CaptureFile) => void

/**
 * Fetch the list of all captured files from the backend.
 */
export async function fetchCaptures(): Promise<CaptureFile[]> {
  const res = await fetch('/api/captures')
  if (!res.ok) {
    throw new Error(`Failed to fetch captures: ${res.status}`)
  }
  const data: CapturesResponse = await res.json()
  return data.captures
}

/**
 * Subscribe to real-time attachment events via SSE.
 * Returns a cleanup function to close the connection.
 */
export function subscribeEvents(onNewCapture: CaptureEventHandler): () => void {
  const es = new EventSource('/api/events')

  es.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data)
      if (data.type === 'new_attachment') {
        onNewCapture(data as CaptureFile)
      }
    } catch {
      // ignore malformed events
    }
  }

  es.onerror = () => {
    // EventSource auto-reconnects
  }

  return () => {
    es.close()
  }
}
