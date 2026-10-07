export type Held = {
  id: string
  path: string
  png: string
  width: number
  height: number
  /** The show_image call that held it; absent for /show-image. */
  toolUseId?: string
}

declare module 'claude-code' {
  interface PluginState {
    'show-image': { held: Held[]; count: number }
  }
}
